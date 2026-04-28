// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAgentManifestStorage} from "../libraries/LibAgentManifestStorage.sol";
import {LibAgentPermissionStorage} from "../libraries/LibAgentPermissionStorage.sol";
import {LibAgentExecutionStorage} from "../libraries/LibAgentExecutionStorage.sol";
import {IUserStateINFT} from "../interfaces/IUserStateINFT.sol";
import {IUserStateLedger} from "../interfaces/IUserStateLedger.sol";
import {IWorkflowCallback} from "../interfaces/IWorkflowCallback.sol";

/// @title AgentExecutionFacet
/// @notice The request/ack/complete/fail state machine for an agent diamond.
///
///         Two entry points for `request`:
///           - request(...)         : called by a trusted workflow contract
///           - userRequest(...)     : called directly by the iNFT owner
///                                    (single-agent / Phase-1 use case;
///                                    a workflow with steps.length == 1)
///
///         On `complete`, the facet:
///           1. validates the worker is authorized,
///           2. validates output type matches the manifest,
///           3. writes a StateItem into UserStateLedger (which re-checks
///              authorization in UserStateINFT),
///           4. emits StepCompleted.
///
///         Payment release is intentionally NOT done here in Phase 1 — that's
///         the workflow + treasury's job in Phase 2. We expose enough event data
///         that an off-chain indexer or a Phase-2 escrow contract can settle.
contract AgentExecutionFacet {
    using LibAgentExecutionStorage for LibAgentExecutionStorage.Layout;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event ExecutionConfigUpdated(
        address userStateINFT,
        address userStateLedger
    );

    event StepRequested(
        bytes32 indexed requestKey,
        uint256 indexed runId,
        uint256 stepIndex,
        address indexed user,
        uint256 tokenId,
        bytes32 inputPointer,
        bytes32 inputType,
        address workflow
    );

    event StepAcknowledged(
        bytes32 indexed requestKey,
        uint256 indexed runId,
        uint256 stepIndex,
        address worker
    );

    event StepCompleted(
        bytes32 indexed requestKey,
        uint256 indexed runId,
        uint256 stepIndex,
        bytes32 outputPointer,
        bytes32 outputType,
        bytes32 outputHash,
        uint256 ledgerItemId
    );

    event StepFailed(
        bytes32 indexed requestKey,
        uint256 indexed runId,
        uint256 stepIndex,
        bytes32 reasonHash
    );

    event StepCancelled(
        bytes32 indexed requestKey,
        uint256 indexed runId,
        uint256 stepIndex
    );

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error NotAdmin();
    error NotWorker();
    error NotTrustedCaller();
    error NotOwnerOfToken();
    error AgentPaused();
    error UnsupportedInputType();
    error WrongOutputType();
    error UnknownRequest();
    error AlreadyTerminal();
    error WrongStatus();
    error UserNotAuthorized();
    error LedgerNotConfigured();
    error INFTNotConfigured();

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------

    modifier onlyAdmin() {
        if (msg.sender != LibDiamond.contractOwner()) revert NotAdmin();
        _;
    }

    modifier onlyWorker() {
        if (
            msg.sender != LibDiamond.contractOwner() &&
            !LibAgentPermissionStorage.layout().workers[msg.sender]
        ) revert NotWorker();
        _;
    }

    // ---------------------------------------------------------------------
    // Config
    // ---------------------------------------------------------------------

    /// @notice Set the protocol-level addresses this agent talks to.
    /// @dev    Admin-only. Stored in execution storage so admin rotation is supported.
    function setExecutionConfig(
        address _userStateINFT,
        address _userStateLedger
    ) external onlyAdmin {
        LibAgentExecutionStorage.Layout storage s = LibAgentExecutionStorage
            .layout();
        s.userStateINFT = _userStateINFT;
        s.userStateLedger = _userStateLedger;
        emit ExecutionConfigUpdated(_userStateINFT, _userStateLedger);
    }

    function getExecutionConfig()
        external
        view
        returns (address inft, address ledger)
    {
        LibAgentExecutionStorage.Layout storage s = LibAgentExecutionStorage
            .layout();
        return (s.userStateINFT, s.userStateLedger);
    }

    // ---------------------------------------------------------------------
    // request — entry from a workflow contract
    // ---------------------------------------------------------------------

    /// @notice Called by a trusted workflow contract to enqueue a step.
    function request(
        address user,
        uint256 tokenId,
        bytes32 inputPointer,
        bytes32 inputType,
        uint256 runId,
        uint256 stepIndex
    ) external returns (bytes32 requestKey) {
        // workflow contract is the caller
        if (
            msg.sender != LibDiamond.contractOwner() &&
            !LibAgentPermissionStorage.layout().trustedCallers[msg.sender]
        ) revert NotTrustedCaller();

        return
            _createRequest(
                msg.sender,
                user,
                tokenId,
                inputPointer,
                inputType,
                runId,
                stepIndex
            );
    }

    /// @notice Called directly by an iNFT owner for a single-agent (1-step) execution.
    /// @dev    workflow == address(0) and runId is auto-assigned.
    function userRequest(
        uint256 tokenId,
        bytes32 inputPointer,
        bytes32 inputType
    ) external returns (bytes32 requestKey, uint256 runId) {
        LibAgentExecutionStorage.Layout storage s = LibAgentExecutionStorage
            .layout();

        if (s.userStateINFT == address(0)) revert INFTNotConfigured();

        // ownership check ONLY (no workflow auth here)
        if (IUserStateINFT(s.userStateINFT).ownerOf(tokenId) != msg.sender) {
            revert NotOwnerOfToken();
        }

        runId = ++s.directRequestCounter;

        requestKey = _createRequest(
            address(0),
            msg.sender,
            tokenId,
            inputPointer,
            inputType,
            runId,
            0
        );
    }

    struct CreateReqParams {
        address workflow;
        address user;
        uint256 tokenId;
        bytes32 inputPointer;
        bytes32 inputType;
        uint256 runId;
        uint256 stepIndex;
    }

    function _createRequest(
        address workflow,
        address user,
        uint256 tokenId,
        bytes32 inputPointer,
        bytes32 inputType,
        uint256 runId,
        uint256 stepIndex
    ) internal returns (bytes32 requestKey) {
        return
            _createRequestInner(
                CreateReqParams({
                    workflow: workflow,
                    user: user,
                    tokenId: tokenId,
                    inputPointer: inputPointer,
                    inputType: inputType,
                    runId: runId,
                    stepIndex: stepIndex
                })
            );
    }

    function _createRequestInner(
        CreateReqParams memory p
    ) internal returns (bytes32 requestKey) {
        LibAgentManifestStorage.AgentManifest
            storage m = LibAgentManifestStorage.layout().manifest;
        if (m.paused) revert AgentPaused();
        if (!_supportsInput(m, p.inputType)) revert UnsupportedInputType();

        LibAgentExecutionStorage.Layout storage s = LibAgentExecutionStorage
            .layout();

        // Verify the user has authorized this agent (or the orchestrating
        // workflow) for this output type / workflow context.
        // workflow == address(0)  → direct user request, auth target = this agent
        // workflow != address(0)  → workflow request, auth target = the workflow
        // The latter lets the user grant once at workflow scope rather than
        // having to authorize every agent in the pipeline.
        if (s.userStateINFT == address(0)) revert INFTNotConfigured();
        address authTarget = p.workflow == address(0)
            ? address(this)
            : p.workflow;
        uint256 wfId = p.workflow == address(0)
            ? 0
            : uint256(uint160(p.workflow));
        if (
            !IUserStateINFT(s.userStateINFT).isAuthorizedFor(
                p.tokenId,
                authTarget,
                m.outputType,
                wfId
            )
        ) {
            revert UserNotAuthorized();
        }

        requestKey = LibAgentExecutionStorage.requestKey(
            p.workflow,
            p.runId,
            p.stepIndex
        );
        LibAgentExecutionStorage.RequestRecord storage r = s.requests[
            requestKey
        ];
        if (r.status != LibAgentExecutionStorage.RequestStatus.NONE)
            revert WrongStatus();

        r.workflow = p.workflow;
        r.runId = p.runId;
        r.stepIndex = p.stepIndex;
        r.user = p.user;
        r.tokenId = p.tokenId;
        r.inputPointer = p.inputPointer;
        r.inputType = p.inputType;
        r.status = LibAgentExecutionStorage.RequestStatus.CREATED;
        r.createdAt = uint64(block.timestamp);
        r.updatedAt = uint64(block.timestamp);

        s.requestKeys.push(requestKey);
        s.userRequests[p.user].push(requestKey);

        emit StepRequested(
            requestKey,
            p.runId,
            p.stepIndex,
            p.user,
            p.tokenId,
            p.inputPointer,
            p.inputType,
            p.workflow
        );
    }

    // ---------------------------------------------------------------------
    // acknowledge — worker says "I picked it up"
    // ---------------------------------------------------------------------

    function acknowledge(bytes32 requestKey) external onlyWorker {
        LibAgentExecutionStorage.RequestRecord
            storage r = LibAgentExecutionStorage.layout().requests[requestKey];
        if (r.status == LibAgentExecutionStorage.RequestStatus.NONE)
            revert UnknownRequest();
        if (r.status != LibAgentExecutionStorage.RequestStatus.CREATED)
            revert WrongStatus();

        r.status = LibAgentExecutionStorage.RequestStatus.PROCESSING;
        r.updatedAt = uint64(block.timestamp);

        emit StepAcknowledged(requestKey, r.runId, r.stepIndex, msg.sender);
    }

    // ---------------------------------------------------------------------
    // complete — worker submits output
    // ---------------------------------------------------------------------

    function complete(
        bytes32 requestKey,
        bytes32 outputPointer,
        bytes32 outputType,
        bytes32 outputHash,
        bytes32 labelHash,
        IUserStateLedger.Visibility visibility
    ) external onlyWorker returns (uint256 ledgerItemId) {
        LibAgentExecutionStorage.Layout storage s = LibAgentExecutionStorage
            .layout();
        LibAgentExecutionStorage.RequestRecord storage r = s.requests[
            requestKey
        ];

        if (r.status == LibAgentExecutionStorage.RequestStatus.NONE)
            revert UnknownRequest();
        if (
            r.status != LibAgentExecutionStorage.RequestStatus.CREATED &&
            r.status != LibAgentExecutionStorage.RequestStatus.PROCESSING
        ) revert AlreadyTerminal();

        LibAgentManifestStorage.AgentManifest
            storage m = LibAgentManifestStorage.layout().manifest;
        if (outputType != m.outputType) revert WrongOutputType();

        if (s.userStateLedger == address(0)) revert LedgerNotConfigured();

        // Update record before external call (CEI pattern — even though ledger is trusted,
        // we want idempotency to come from the status check above)
        r.outputPointer = outputPointer;
        r.outputType = outputType;
        r.outputHash = outputHash;
        r.status = LibAgentExecutionStorage.RequestStatus.COMPLETED;
        r.updatedAt = uint64(block.timestamp);

        // Append to user's ledger. Ledger re-checks authorization; if revoked
        // mid-flight the ledger will revert and the whole complete() reverts,
        // leaving the request in PROCESSING / CREATED for retry or admin cancel.
        // The workflow address (or 0 for direct) is what the ledger uses as
        // its auth target — see UserStateLedger.appendItem.
        IUserStateLedger.StateItem memory item = IUserStateLedger.StateItem({
            itemType: outputType,
            pointer: outputPointer,
            contentHash: outputHash,
            labelHash: labelHash,
            runId: r.runId,
            stepIndex: r.stepIndex,
            visibility: visibility
        });
        ledgerItemId = IUserStateLedger(s.userStateLedger).appendItem(
            r.tokenId,
            r.workflow,
            item
        );

        emit StepCompleted(
            requestKey,
            r.runId,
            r.stepIndex,
            outputPointer,
            outputType,
            outputHash,
            ledgerItemId
        );

        // Notify the workflow if this request was workflow-orchestrated.
        // Wrapped in try/catch so a buggy workflow can't lock the worker out
        // of getting their step recorded — the workflow can recover via poke().
        if (r.workflow != address(0)) {
            try
                IWorkflowCallback(r.workflow).onStepCompleted(
                    r.runId,
                    r.stepIndex,
                    outputPointer,
                    outputType,
                    outputHash
                )
            {} catch {
                // intentionally swallow — workflow can be poked manually
            }
        }
    }

    // ---------------------------------------------------------------------
    // fail / cancel
    // ---------------------------------------------------------------------

    function fail(bytes32 requestKey, bytes32 reasonHash) external onlyWorker {
        LibAgentExecutionStorage.RequestRecord
            storage r = LibAgentExecutionStorage.layout().requests[requestKey];
        if (r.status == LibAgentExecutionStorage.RequestStatus.NONE)
            revert UnknownRequest();
        if (
            r.status != LibAgentExecutionStorage.RequestStatus.CREATED &&
            r.status != LibAgentExecutionStorage.RequestStatus.PROCESSING
        ) revert AlreadyTerminal();

        r.status = LibAgentExecutionStorage.RequestStatus.FAILED;
        r.updatedAt = uint64(block.timestamp);
        emit StepFailed(requestKey, r.runId, r.stepIndex, reasonHash);

        if (r.workflow != address(0)) {
            try
                IWorkflowCallback(r.workflow).onStepFailed(
                    r.runId,
                    r.stepIndex,
                    reasonHash
                )
            {} catch {}
        }
    }

    /// @notice Cancellable by either the trusted caller (workflow) that opened
    ///         the request, or by the user themselves (for direct userRequests),
    ///         or by the agent admin.
    function cancel(bytes32 requestKey) external {
        LibAgentExecutionStorage.RequestRecord
            storage r = LibAgentExecutionStorage.layout().requests[requestKey];
        if (r.status == LibAgentExecutionStorage.RequestStatus.NONE)
            revert UnknownRequest();
        if (
            r.status != LibAgentExecutionStorage.RequestStatus.CREATED &&
            r.status != LibAgentExecutionStorage.RequestStatus.PROCESSING
        ) revert AlreadyTerminal();

        bool allowed = msg.sender == LibDiamond.contractOwner() ||
            msg.sender == r.workflow ||
            (r.workflow == address(0) && msg.sender == r.user);
        if (!allowed) revert NotAdmin();

        r.status = LibAgentExecutionStorage.RequestStatus.CANCELLED;
        r.updatedAt = uint64(block.timestamp);
        emit StepCancelled(requestKey, r.runId, r.stepIndex);

        // If a workflow opened the request and someone else (admin/user)
        // cancelled it, notify the workflow. If the workflow itself called
        // cancel() this is a no-op-ish callback — the workflow can ignore
        // its own re-entry, or use it to update state in a single tx.
        if (r.workflow != address(0)) {
            try
                IWorkflowCallback(r.workflow).onStepCancelled(
                    r.runId,
                    r.stepIndex
                )
            {} catch {}
        }
    }

    // ---------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------

    function getRequest(
        bytes32 requestKey
    ) external view returns (LibAgentExecutionStorage.RequestRecord memory) {
        return LibAgentExecutionStorage.layout().requests[requestKey];
    }

    function getRequestKeysForUser(
        address user
    ) external view returns (bytes32[] memory) {
        return LibAgentExecutionStorage.layout().userRequests[user];
    }

    function getAllRequestKeys(
        uint256 cursor,
        uint256 limit
    ) external view returns (bytes32[] memory page, uint256 nextCursor) {
        bytes32[] storage all = LibAgentExecutionStorage.layout().requestKeys;
        if (cursor >= all.length) return (new bytes32[](0), all.length);
        uint256 end = cursor + limit;
        if (end > all.length) end = all.length;
        page = new bytes32[](end - cursor);
        for (uint256 i = cursor; i < end; i++) {
            page[i - cursor] = all[i];
        }
        nextCursor = end;
    }

    function totalRequests() external view returns (uint256) {
        return LibAgentExecutionStorage.layout().requestKeys.length;
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _supportsInput(
        LibAgentManifestStorage.AgentManifest storage m,
        bytes32 t
    ) internal view returns (bool) {
        for (uint256 i = 0; i < m.inputTypes.length; i++) {
            if (m.inputTypes[i] == t) return true;
        }
        return false;
    }
}
