// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAgentExecution} from "./interfaces/IAgentExecution.sol";
import {IProtocolTreasury} from "./interfaces/IProtocolTreasury.sol";

contract WorkflowInstance {
    struct StepSpec {
        address agent;
        uint256 cost;
        address payoutAddress;
        bytes32 inputType;
        bytes32 outputType;
    }

    struct Run {
        address user;
        uint256 tokenId;
        uint256 currentStepIndex;
        bytes32 currentInputPointer;
        bytes32 currentInputType;
        uint8 status; // 1 = active, 2 = done
    }

    StepSpec[] internal _steps;
    uint256 internal _totalCost;

    uint256 public nextRunId;

    mapping(uint256 => Run) internal _runs;
    mapping(uint256 => mapping(uint256 => bytes32)) internal _keys;

    // ✅ NEW
    mapping(address => uint256[]) public userRuns;

    IProtocolTreasury public immutable treasury;

    constructor(address _treasury, StepSpec[] memory steps) {
        require(_treasury != address(0), "BAD_TREASURY");
        require(steps.length > 0, "NO_STEPS");

        treasury = IProtocolTreasury(_treasury);

        uint256 cost;

        for (uint256 i = 0; i < steps.length; i++) {
            require(steps[i].agent != address(0), "BAD_AGENT");
            require(steps[i].payoutAddress != address(0), "BAD_PAYOUT");

            _steps.push(steps[i]);
            cost += steps[i].cost;
        }

        _totalCost = cost;
    }

    function totalCost() external view returns (uint256) {
        return _totalCost;
    }

    // ✅ RETURN runId
    function start(
        uint256 tokenId,
        bytes32 inputPointer
    ) external payable returns (uint256 runId) {
        require(msg.value == _totalCost, "WRONG_VALUE");

        runId = ++nextRunId;

        // ✅ track user history
        userRuns[msg.sender].push(runId);

        treasury.deposit{value: msg.value}(runId, msg.sender);

        Run storage r = _runs[runId];

        r.user = msg.sender;
        r.tokenId = tokenId;
        r.currentStepIndex = 0;
        r.currentInputPointer = inputPointer;
        r.currentInputType = _steps[0].inputType;
        r.status = 1;

        _request(runId, 0);
    }

    function _request(uint256 runId, uint256 stepIndex) internal {
        Run storage r = _runs[runId];
        StepSpec storage s = _steps[stepIndex];

        bytes32 key = IAgentExecution(s.agent).request(
            r.user,
            r.tokenId,
            r.currentInputPointer,
            r.currentInputType,
            runId,
            stepIndex
        );

        _keys[runId][stepIndex] = key;
    }

    function onStepCompleted(
        uint256 runId,
        uint256 stepIndex,
        bytes32 outputPointer,
        bytes32 outputType,
        bytes32
    ) external {
        Run storage r = _runs[runId];
        StepSpec storage s = _steps[stepIndex];

        require(r.status == 1, "NOT_ACTIVE");
        require(msg.sender == s.agent, "BAD_AGENT");
        require(stepIndex == r.currentStepIndex, "BAD_STEP");

        treasury.releaseTo(runId, s.payoutAddress, s.cost);

        if (stepIndex + 1 == _steps.length) {
            treasury.settle(runId, r.user);
            r.status = 2;
        } else {
            r.currentStepIndex++;
            r.currentInputPointer = outputPointer;
            r.currentInputType = outputType;

            _request(runId, stepIndex + 1);
        }
    }

    // ✅ NEW: query run
    function getRun(uint256 runId) external view returns (Run memory) {
        return _runs[runId];
    }

    // ✅ NEW: user history
    function getUserRuns(
        address user
    ) external view returns (uint256[] memory) {
        return userRuns[user];
    }

    // ✅ NEW: step → key
    function getStepKey(
        uint256 runId,
        uint256 stepIndex
    ) external view returns (bytes32) {
        return _keys[runId][stepIndex];
    }
}
