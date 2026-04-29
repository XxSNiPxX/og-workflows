// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IWorkflowCallback} from "./IWorkflowCallback.sol";

interface IWorkflowInstance is IWorkflowCallback {
    enum RunStatus {
        NONE,
        RUNNING,
        COMPLETED,
        FAILED,
        CANCELLED
    }

    struct StepSpec {
        address agent;
        bytes32 inputType;
        bytes32 outputType;
        uint256 cost;
        address payoutAddress;
    }

    struct Run {
        address user;
        uint256 tokenId;
        uint256 currentStepIndex;
        bytes32 currentInputPointer;
        bytes32 currentInputType;
        uint256 deposited;
        RunStatus status;
        uint64 startedAt;
        uint64 updatedAt;
    }

    // ===== EVENTS =====

    event RunStarted(
        uint256 indexed runId,
        address indexed user,
        uint256 tokenId,
        uint256 deposited
    );

    event StepRequested(
        uint256 indexed runId,
        uint256 stepIndex,
        address agent,
        bytes32 requestKey
    );

    event StepResolved(
        uint256 indexed runId,
        uint256 stepIndex,
        RunStatus runStatus
    );

    event RunCompleted(uint256 indexed runId, bytes32 finalOutputPointer);

    event RunFailed(
        uint256 indexed runId,
        uint256 stepIndex,
        bytes32 reasonHash
    );

    event RunCancelled(uint256 indexed runId, uint256 stepIndex);

    // ===== CORE =====

    function start(
        uint256 tokenId,
        bytes32 inputPointer
    ) external payable returns (uint256 runId);

    function poke(uint256 runId) external;

    function cancelRun(uint256 runId) external;

    // ===== VIEWS =====

    function totalCost() external view returns (uint256);

    function stepCount() external view returns (uint256);

    function getStep(uint256 stepIndex) external view returns (StepSpec memory);

    function getRun(uint256 runId) external view returns (Run memory);

    function getRequestKey(
        uint256 runId,
        uint256 stepIndex
    ) external view returns (bytes32);
}
