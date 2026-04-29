// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IWorkflowInstance} from "./interfaces/IWorkflowInstance.sol";
import {IAgentExecution} from "./interfaces/IAgentExecution.sol";
import {IUserStateINFT} from "./interfaces/IUserStateINFT.sol";
import {IProtocolTreasury} from "./interfaces/IProtocolTreasury.sol";
import {IUserStateLedger} from "./interfaces/IUserStateLedger.sol";

contract WorkflowInstance is IWorkflowInstance {
    address public immutable factory;
    address public immutable creator;
    address public immutable admin;
    IUserStateINFT public immutable inft;
    IProtocolTreasury public immutable treasury;
    IUserStateLedger public immutable ledger;

    string public name;
    string public description;

    StepSpec[] internal _steps;
    uint256 internal immutable _totalCost;

    uint256 public nextRunId;
    mapping(uint256 => Run) internal _runs;
    mapping(uint256 => mapping(uint256 => bytes32)) internal _requestKeys;

    error NotOwnerOfToken();
    error InsufficientPayment();
    error UnknownRun();
    error NotAuthorized();
    error RunNotActive();
    error WrongCallback();
    error WrongOutputType();
    error NotUserOrAdmin();
    error TransferFailed();
    error NoStepsExecuted();

    struct InitParams {
        address factory;
        address creator;
        address admin;
        address inft;
        address treasury;
        address ledger;
        StepSpec[] steps;
        string name;
        string description;
    }

    constructor(InitParams memory p) {
        require(p.factory != address(0), "factory zero");
        require(p.inft != address(0), "inft zero");
        require(p.treasury != address(0), "treasury zero");
        require(p.ledger != address(0), "ledger zero");
        require(p.steps.length > 0, "empty workflow");

        factory = p.factory;
        creator = p.creator;
        admin = p.admin == address(0) ? p.creator : p.admin;
        inft = IUserStateINFT(p.inft);
        treasury = IProtocolTreasury(p.treasury);
        ledger = IUserStateLedger(p.ledger);
        name = p.name;
        description = p.description;

        uint256 cost;
        for (uint256 i = 0; i < p.steps.length; i++) {
            _steps.push(p.steps[i]);
            cost += p.steps[i].cost;
        }
        _totalCost = cost;
    }

    function inputType() external view returns (bytes32) {
        return _steps[0].inputType;
    }

    function outputType() external view returns (bytes32) {
        return _steps[_steps.length - 1].outputType;
    }

    function start(
        uint256 tokenId,
        bytes32 inputPointer
    ) external payable override returns (uint256 runId) {
        if (msg.value < _totalCost) revert InsufficientPayment();

        // Capability-based check: workflow must be authorized for this token.
        // Ownership is still expected in the normal flow, but the pipeline
        // should not depend on a strict owner-only path for execution.
        if (!inft.isAuthorized(tokenId, address(this))) revert NotAuthorized();

        runId = ++nextRunId;

        treasury.deposit{value: _totalCost}(runId, msg.sender);

        if (msg.value > _totalCost) {
            (bool ok, ) = msg.sender.call{value: msg.value - _totalCost}("");
            if (!ok) revert TransferFailed();
        }

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

        _requestStep(runId, 0);
    }

    function onStepCompleted(
        uint256 runId,
        uint256 stepIndex,
        bytes32 outputPointer,
        bytes32 outputType_,
        bytes32 outputHash
    ) external override {
        Run storage r = _runs[runId];
        if (r.status != RunStatus.RUNNING) revert RunNotActive();
        if (r.currentStepIndex != stepIndex) revert WrongCallback();
        if (msg.sender != _steps[stepIndex].agent) revert WrongCallback();
        if (outputType_ != _steps[stepIndex].outputType)
            revert WrongOutputType();

        _settleStep(runId, stepIndex, outputPointer, outputHash);
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

    function onStepCancelled(
        uint256 runId,
        uint256 stepIndex
    ) external override {
        Run storage r = _runs[runId];
        if (r.status != RunStatus.RUNNING) return;
        if (r.currentStepIndex != stepIndex) return;
        if (msg.sender != _steps[stepIndex].agent) return;

        _cancelRun(runId, stepIndex);
    }

    function poke(uint256 runId) external override {
        Run storage r = _runs[runId];
        if (r.status == RunStatus.NONE) revert UnknownRun();
        if (r.status != RunStatus.RUNNING) return;

        uint256 stepIndex = r.currentStepIndex;
        bytes32 reqKey = _requestKeys[runId][stepIndex];
        if (reqKey == bytes32(0)) revert NoStepsExecuted();

        IAgentExecution agent = IAgentExecution(_steps[stepIndex].agent);
        IAgentExecution.RequestRecord memory req = agent.getRequest(reqKey);

        if (req.status == IAgentExecution.RequestStatus.COMPLETED) {
            if (req.outputType != _steps[stepIndex].outputType) {
                revert WrongOutputType();
            }
            _settleStep(runId, stepIndex, req.outputPointer, req.outputHash);
        } else if (req.status == IAgentExecution.RequestStatus.FAILED) {
            _failRun(runId, stepIndex, bytes32(0));
        } else if (req.status == IAgentExecution.RequestStatus.CANCELLED) {
            _cancelRun(runId, stepIndex);
        }
    }

    function cancelRun(uint256 runId) external override {
        Run storage r = _runs[runId];
        if (r.status == RunStatus.NONE) revert UnknownRun();
        if (r.status != RunStatus.RUNNING) revert RunNotActive();
        if (msg.sender != r.user && msg.sender != admin) {
            revert NotUserOrAdmin();
        }

        bytes32 reqKey = _requestKeys[runId][r.currentStepIndex];
        IAgentExecution(_steps[r.currentStepIndex].agent).cancel(reqKey);
    }

    function _settleStep(
        uint256 runId,
        uint256 stepIndex,
        bytes32 outputPointer,
        bytes32 outputHash
    ) internal {
        Run storage r = _runs[runId];
        StepSpec storage step = _steps[stepIndex];

        // 1. WRITE TO LEDGER (internal effect)
        ledger.appendItem(
            r.tokenId,
            address(this),
            IUserStateLedger.StateItem({
                itemType: step.outputType,
                pointer: outputPointer,
                contentHash: outputHash,
                labelHash: bytes32(0),
                runId: runId,
                stepIndex: stepIndex,
                visibility: IUserStateLedger.Visibility.PRIVATE_SUMMARY
            })
        );

        // 2. ADVANCE STATE FIRST (CRITICAL FIX)
        bool isLast = (stepIndex + 1 == _steps.length);

        if (!isLast) {
            r.currentStepIndex = stepIndex + 1;
            r.currentInputPointer = outputPointer;
            r.currentInputType = _steps[stepIndex + 1].inputType;
        }

        r.updatedAt = uint64(block.timestamp);

        // 3. THEN EXTERNAL CALLS (safe ordering)

        if (step.cost > 0) {
            treasury.releaseTo(runId, step.payoutAddress, step.cost);
        }

        emit StepResolved(runId, stepIndex, RunStatus.RUNNING);

        if (isLast) {
            r.status = RunStatus.COMPLETED;
            treasury.settle(runId, r.user);
            emit RunCompleted(runId, outputPointer);
        } else {
            try this._requestStepExternal(runId, stepIndex + 1) {} catch {
                _failRun(runId, stepIndex + 1, keccak256("requestNextFailed"));
            }
        }
    }

    function _failRun(
        uint256 runId,
        uint256 stepIndex,
        bytes32 reasonHash
    ) internal {
        Run storage r = _runs[runId];
        r.status = RunStatus.FAILED;
        r.updatedAt = uint64(block.timestamp);
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

        bytes32 key = IAgentExecution(step.agent).request(
            r.user,
            r.tokenId,
            r.currentInputPointer,
            r.currentInputType,
            runId,
            stepIndex
        );

        _requestKeys[runId][stepIndex] = key;
        emit StepRequested(runId, stepIndex, step.agent, key);
    }

    function _requestStepExternal(uint256 runId, uint256 stepIndex) external {
        require(msg.sender == address(this), "WI: only self");
        _requestStep(runId, stepIndex);
    }

    function totalCost() external view override returns (uint256) {
        return _totalCost;
    }

    function stepCount() external view override returns (uint256) {
        return _steps.length;
    }

    function getStep(
        uint256 i
    ) external view override returns (StepSpec memory) {
        return _steps[i];
    }

    function getRun(uint256 runId) external view override returns (Run memory) {
        return _runs[runId];
    }

    function getRequestKey(
        uint256 runId,
        uint256 stepIndex
    ) external view override returns (bytes32) {
        return _requestKeys[runId][stepIndex];
    }
}
