// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IWorkflowInstance} from "./interfaces/IWorkflowInstance.sol";
import {IAgentExecution} from "./interfaces/IAgentExecution.sol";
import {IUserStateINFT} from "./interfaces/IUserStateINFT.sol";
import {IProtocolTreasury} from "./interfaces/IProtocolTreasury.sol";

/// @title WorkflowInstance
/// @notice One per workflow definition. Frozen at construction:
///         - the StepSpec[] (agent / I/O types / cost / payout snapshot)
///         - the I/O type chain (validated by WorkflowFactory before deploy)
///         - totalCost
///
///         Lifecycle of a run:
///           1. user calls start(tokenId, inputPointer) with msg.value == totalCost
///              → workflow deposits funds in treasury, requests step 0 on agent[0]
///           2. worker on agent[i] does work, calls agent[i].complete(...)
///           3. agent's complete() try-calls workflow.onStepCompleted(...)
///              → workflow releases payment, requests next step (or finalises)
///           4. on the last step: workflow settles escrow (refunds any leftover)
///              and marks run COMPLETED
///
///         Failure paths:
///           - agent.fail callback → workflow refunds remaining escrow + step
///             that failed (worker who said "no result" doesn't get paid)
///           - user calls cancelRun → workflow cancels in-flight step on agent
///             → agent's cancel callback → workflow refunds remaining
///           - callback missed (revert/OOG/etc) → anyone calls poke(runId) to
///             pull the agent's status and progress the run
contract WorkflowInstance is IWorkflowInstance {
    // ---------------------------------------------------------------------
    // Immutable wiring (set at construction)
    // ---------------------------------------------------------------------

    address public immutable factory;
    address public immutable creator;
    address public immutable admin;
    IUserStateINFT public immutable inft;
    IProtocolTreasury public immutable treasury;

    string public name;
    string public description;

    StepSpec[] internal _steps;
    uint256 internal immutable _totalCost;

    // ---------------------------------------------------------------------
    // Run state
    // ---------------------------------------------------------------------

    uint256 public nextRunId; // 1-indexed
    mapping(uint256 => Run) internal _runs;
    // (runId, stepIndex) => requestKey returned by agent.request()
    mapping(uint256 => mapping(uint256 => bytes32)) internal _requestKeys;

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error NotOwnerOfToken();
    error InsufficientPayment();
    error UnknownRun();
    error RunNotActive();
    error WrongCallback();
    error WrongOutputType();
    error NotUserOrAdmin();
    error TransferFailed();
    error NoStepsExecuted();

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    /// @dev Parameters bundled to keep the constructor under the stack limit.
    struct InitParams {
        address factory;
        address creator;
        address admin;
        address inft;
        address treasury;
        StepSpec[] steps;
        string name;
        string description;
    }

    constructor(InitParams memory p) {
        require(p.factory != address(0), "WI: factory zero");
        require(p.inft != address(0), "WI: inft zero");
        require(p.treasury != address(0), "WI: treasury zero");
        require(p.steps.length > 0, "WI: empty workflow");

        factory = p.factory;
        creator = p.creator;
        admin = p.admin == address(0) ? p.creator : p.admin;
        inft = IUserStateINFT(p.inft);
        treasury = IProtocolTreasury(p.treasury);
        name = p.name;
        description = p.description;

        uint256 cost;
        for (uint256 i = 0; i < p.steps.length; i++) {
            _steps.push(p.steps[i]);
            cost += p.steps[i].cost;
        }
        _totalCost = cost;
    }

    // ---------------------------------------------------------------------
    // start
    // ---------------------------------------------------------------------

    function start(uint256 tokenId, bytes32 inputPointer)
        external
        payable
        override
        returns (uint256 runId)
    {
        if (msg.value < _totalCost) revert InsufficientPayment();
        if (inft.ownerOf(tokenId) != msg.sender) revert NotOwnerOfToken();

        runId = ++nextRunId;
        Run storage r = _runs[runId];
        r.user = msg.sender;
        r.tokenId = tokenId;
        r.currentStepIndex = 0;
        r.currentInputPointer = inputPointer;
        r.currentInputType = _steps[0].inputType;
        r.deposited = _totalCost;
        r.status = RunStatus.RUNNING;
        r.startedAt = uint64(block.timestamp);
        r.updatedAt = uint64(block.timestamp);

        emit RunStarted(runId, msg.sender, tokenId, _totalCost);

        // Deposit exactly _totalCost into treasury; refund any over-payment to user.
        treasury.deposit{value: _totalCost}(runId, msg.sender);
        if (msg.value > _totalCost) {
            (bool ok, ) = msg.sender.call{value: msg.value - _totalCost}("");
            if (!ok) revert TransferFailed();
        }

        // Request the first step.
        _requestStep(runId, 0);
    }

    // ---------------------------------------------------------------------
    // Callbacks (called by agent.complete/fail/cancel)
    // ---------------------------------------------------------------------

    function onStepCompleted(
        uint256 runId,
        uint256 stepIndex,
        bytes32 outputPointer,
        bytes32 outputType_,
        bytes32 /*outputHash*/
    ) external override {
        Run storage r = _runs[runId];
        if (r.status != RunStatus.RUNNING) revert RunNotActive();
        if (r.currentStepIndex != stepIndex) revert WrongCallback();
        if (msg.sender != _steps[stepIndex].agent) revert WrongCallback();
        if (outputType_ != _steps[stepIndex].outputType) revert WrongOutputType();

        _settleStep(runId, stepIndex, outputPointer);
    }

    function onStepFailed(
        uint256 runId,
        uint256 stepIndex,
        bytes32 reasonHash
    ) external override {
        Run storage r = _runs[runId];
        if (r.status != RunStatus.RUNNING) revert RunNotActive();
        if (r.currentStepIndex != stepIndex) revert WrongCallback();
        if (msg.sender != _steps[stepIndex].agent) revert WrongCallback();

        _failRun(runId, stepIndex, reasonHash);
    }

    function onStepCancelled(uint256 runId, uint256 stepIndex) external override {
        Run storage r = _runs[runId];
        // If we already moved on (e.g. user called cancelRun and we already
        // marked CANCELLED), this is a no-op.
        if (r.status != RunStatus.RUNNING) return;
        if (r.currentStepIndex != stepIndex) return;
        if (msg.sender != _steps[stepIndex].agent) return;

        _cancelRun(runId, stepIndex);
    }

    // ---------------------------------------------------------------------
    // poke — recovery path when callback was missed
    // ---------------------------------------------------------------------

    function poke(uint256 runId) external override {
        Run storage r = _runs[runId];
        if (r.status == RunStatus.NONE) revert UnknownRun();
        if (r.status != RunStatus.RUNNING) return; // already terminal

        uint256 stepIndex = r.currentStepIndex;
        bytes32 reqKey = _requestKeys[runId][stepIndex];
        if (reqKey == bytes32(0)) revert NoStepsExecuted();

        IAgentExecution agent = IAgentExecution(_steps[stepIndex].agent);
        IAgentExecution.RequestRecord memory req = agent.getRequest(reqKey);

        if (req.status == IAgentExecution.RequestStatus.COMPLETED) {
            if (req.outputType != _steps[stepIndex].outputType) revert WrongOutputType();
            _settleStep(runId, stepIndex, req.outputPointer);
        } else if (req.status == IAgentExecution.RequestStatus.FAILED) {
            _failRun(runId, stepIndex, bytes32(0));
        } else if (req.status == IAgentExecution.RequestStatus.CANCELLED) {
            _cancelRun(runId, stepIndex);
        }
        // else: still CREATED / PROCESSING — nothing to do
    }

    // ---------------------------------------------------------------------
    // cancelRun — user-initiated mid-run cancel
    // ---------------------------------------------------------------------

    function cancelRun(uint256 runId) external override {
        Run storage r = _runs[runId];
        if (r.status == RunStatus.NONE) revert UnknownRun();
        if (r.status != RunStatus.RUNNING) revert RunNotActive();
        if (msg.sender != r.user && msg.sender != admin) revert NotUserOrAdmin();

        bytes32 reqKey = _requestKeys[runId][r.currentStepIndex];
        IAgentExecution(_steps[r.currentStepIndex].agent).cancel(reqKey);
        // The agent's cancel() will callback onStepCancelled which finalises
        // the run. If the callback reverted (try/catch in the agent), the run
        // is still in RUNNING; anyone can poke() it to finalise.
    }

    // ---------------------------------------------------------------------
    // Internal: state transitions
    // ---------------------------------------------------------------------

    function _settleStep(uint256 runId, uint256 stepIndex, bytes32 outputPointer) internal {
        Run storage r = _runs[runId];
        StepSpec storage step = _steps[stepIndex];

        // Pay the agent
        if (step.cost > 0) {
            treasury.releaseTo(runId, step.payoutAddress, step.cost);
        }

        emit StepResolved(runId, stepIndex, RunStatus.RUNNING);

        if (stepIndex + 1 == _steps.length) {
            // Last step — finalise run
            r.status = RunStatus.COMPLETED;
            r.updatedAt = uint64(block.timestamp);
            // Refund any leftover (shouldn't be any in normal flow but defensive)
            treasury.settle(runId, r.user);
            emit RunCompleted(runId, outputPointer);
        } else {
            // Advance to next step
            r.currentStepIndex = stepIndex + 1;
            r.currentInputPointer = outputPointer;
            r.currentInputType = _steps[stepIndex + 1].inputType;
            r.updatedAt = uint64(block.timestamp);

            // try/catch: if requesting next step fails (e.g. user revoked
            // permission, next agent paused), the run is failed and remaining
            // escrow refunded.
            try this._requestStepExternal(runId, stepIndex + 1) {} catch {
                _failRun(runId, stepIndex + 1, keccak256("requestNextFailed"));
            }
        }
    }

    function _failRun(uint256 runId, uint256 stepIndex, bytes32 reasonHash) internal {
        Run storage r = _runs[runId];
        r.status = RunStatus.FAILED;
        r.updatedAt = uint64(block.timestamp);
        // Refund all remaining escrow to user
        treasury.settle(runId, r.user);
        emit RunFailed(runId, stepIndex, reasonHash);
    }

    function _cancelRun(uint256 runId, uint256 stepIndex) internal {
        Run storage r = _runs[runId];
        r.status = RunStatus.CANCELLED;
        r.updatedAt = uint64(block.timestamp);
        treasury.settle(runId, r.user);
        emit RunCancelled(runId, stepIndex);
    }

    function _requestStep(uint256 runId, uint256 stepIndex) internal {
        Run storage r = _runs[runId];
        StepSpec storage step = _steps[stepIndex];
        bytes32 reqKey = IAgentExecution(step.agent).request(
            r.user,
            r.tokenId,
            r.currentInputPointer,
            r.currentInputType,
            runId,
            stepIndex
        );
        _requestKeys[runId][stepIndex] = reqKey;
        emit StepRequested(runId, stepIndex, step.agent, reqKey);
    }

    /// @notice External wrapper around _requestStep so we can try/catch from
    ///         within _settleStep. Restricted to self-call only.
    function _requestStepExternal(uint256 runId, uint256 stepIndex) external {
        require(msg.sender == address(this), "WI: only self");
        _requestStep(runId, stepIndex);
    }

    // ---------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------

    function totalCost() external view override returns (uint256) {
        return _totalCost;
    }

    function stepCount() external view override returns (uint256) {
        return _steps.length;
    }

    function getStep(uint256 stepIndex) external view override returns (StepSpec memory) {
        return _steps[stepIndex];
    }

    function getAllSteps() external view returns (StepSpec[] memory) {
        return _steps;
    }

    function getRun(uint256 runId) external view override returns (Run memory) {
        return _runs[runId];
    }

    function getRequestKey(uint256 runId, uint256 stepIndex) external view override returns (bytes32) {
        return _requestKeys[runId][stepIndex];
    }

    function inputType() external view returns (bytes32) {
        return _steps[0].inputType;
    }

    function outputType() external view returns (bytes32) {
        return _steps[_steps.length - 1].outputType;
    }
}
