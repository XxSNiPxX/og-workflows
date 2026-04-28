// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAgentPermissionStorage} from "../libraries/LibAgentPermissionStorage.sol";
import {LibAgentManifestStorage} from "../libraries/LibAgentManifestStorage.sol";
import {IAgentPermission} from "../interfaces/IAgentPermission.sol";

/// @title AgentPermissionFacet
/// @notice Manages two access lists for an agent diamond:
///         - workers: off-chain processes authorized to ack/complete/fail requests
///         - trustedCallers: contracts (e.g. WorkflowInstance) authorized to call request()
///
///         The agent admin (== diamond owner) is implicitly authorized for both.
contract AgentPermissionFacet is IAgentPermission {
    using LibAgentPermissionStorage for LibAgentPermissionStorage.Layout;

    event WorkerSet(address indexed worker, bool active);
    event TrustedCallerSet(address indexed caller, bool active);
    event WorkflowFactorySet(address indexed factory);
    event WorkflowJoined(address indexed workflow, address indexed factory);

    error ZeroAddress();
    error NotWorkflowFactory();
    error NotWorkflowReady();

    modifier onlyAdmin() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    // ---------------------------------------------------------------------
    // Workers
    // ---------------------------------------------------------------------

    function setWorker(address worker, bool active) external onlyAdmin {
        if (worker == address(0)) revert ZeroAddress();
        LibAgentPermissionStorage.Layout storage s = LibAgentPermissionStorage.layout();

        bool current = s.workers[worker];
        if (current == active) return;

        if (active) {
            s.workers[worker] = true;
            s.workerList.push(worker);
            s.workerIndex[worker] = s.workerList.length; // 1-based
        } else {
            s.workers[worker] = false;
            uint256 idx1 = s.workerIndex[worker]; // 1-based
            uint256 last = s.workerList.length;
            if (idx1 != last) {
                address lastAddr = s.workerList[last - 1];
                s.workerList[idx1 - 1] = lastAddr;
                s.workerIndex[lastAddr] = idx1;
            }
            s.workerList.pop();
            delete s.workerIndex[worker];
        }
        emit WorkerSet(worker, active);
    }

    function isWorker(address account) external view returns (bool) {
        if (account == LibDiamond.contractOwner()) return true;
        return LibAgentPermissionStorage.layout().workers[account];
    }

    function getWorkers() external view returns (address[] memory) {
        return LibAgentPermissionStorage.layout().workerList;
    }

    // ---------------------------------------------------------------------
    // Trusted callers (workflow contracts)
    // ---------------------------------------------------------------------

    function setTrustedCaller(address caller, bool active) external onlyAdmin {
        if (caller == address(0)) revert ZeroAddress();
        LibAgentPermissionStorage.Layout storage s = LibAgentPermissionStorage.layout();

        bool current = s.trustedCallers[caller];
        if (current == active) return;

        if (active) {
            s.trustedCallers[caller] = true;
            s.trustedCallerList.push(caller);
            s.trustedCallerIndex[caller] = s.trustedCallerList.length;
        } else {
            s.trustedCallers[caller] = false;
            uint256 idx1 = s.trustedCallerIndex[caller];
            uint256 last = s.trustedCallerList.length;
            if (idx1 != last) {
                address lastAddr = s.trustedCallerList[last - 1];
                s.trustedCallerList[idx1 - 1] = lastAddr;
                s.trustedCallerIndex[lastAddr] = idx1;
            }
            s.trustedCallerList.pop();
            delete s.trustedCallerIndex[caller];
        }
        emit TrustedCallerSet(caller, active);
    }

    function isTrustedCaller(address account) external view override returns (bool) {
        if (account == LibDiamond.contractOwner()) return true;
        return LibAgentPermissionStorage.layout().trustedCallers[account];
    }

    function getTrustedCallers() external view returns (address[] memory) {
        return LibAgentPermissionStorage.layout().trustedCallerList;
    }

    // ---------------------------------------------------------------------
    // Phase 2: Workflow factory integration
    // ---------------------------------------------------------------------

    /// @notice Admin sets the protocol-wide WorkflowFactory address. The factory
    ///         is the only contract that can permissionlessly self-add workflows
    ///         to the trustedCallers list (gated by `workflowReady`).
    /// @dev    Setting to address(0) disables permissionless joining.
    function setWorkflowFactory(address _factory) external onlyAdmin {
        LibAgentPermissionStorage.layout().workflowFactory = _factory;
        emit WorkflowFactorySet(_factory);
    }

    function getWorkflowFactory() external view override returns (address) {
        return LibAgentPermissionStorage.layout().workflowFactory;
    }

    /// @notice Self-add a workflow to the trustedCallers list. Callable only
    ///         by the registered WorkflowFactory; only succeeds when the agent's
    ///         manifest has `workflowReady = true`.
    /// @dev    This is the wiring that lets WorkflowFactory.createWorkflow
    ///         atomically register the new workflow as a trusted caller across
    ///         every agent in its pipeline, without each agent admin having to
    ///         issue a manual transaction.
    function joinWorkflow(address workflow) external override {
        if (workflow == address(0)) revert ZeroAddress();
        LibAgentPermissionStorage.Layout storage s = LibAgentPermissionStorage.layout();
        if (msg.sender != s.workflowFactory) revert NotWorkflowFactory();

        LibAgentManifestStorage.AgentManifest storage m = LibAgentManifestStorage.layout().manifest;
        if (!m.workflowReady) revert NotWorkflowReady();

        if (s.trustedCallers[workflow]) return; // idempotent

        s.trustedCallers[workflow] = true;
        s.trustedCallerList.push(workflow);
        s.trustedCallerIndex[workflow] = s.trustedCallerList.length;

        emit TrustedCallerSet(workflow, true);
        emit WorkflowJoined(workflow, msg.sender);
    }
}
