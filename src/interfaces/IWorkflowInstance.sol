// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IWorkflowCallback} from "./IWorkflowCallback.sol";

/// @title IWorkflowInstance
/// @notice Surface of a single deployed workflow. Inherits the agent-callback
///         hooks via IWorkflowCallback.
interface IWorkflowInstance is IWorkflowCallback {
    enum RunStatus { NONE, RUNNING, COMPLETED, FAILED, CANCELLED }

    /// @notice Frozen snapshot of one step in the workflow definition.
    struct StepSpec {
        address agent;            // AgentDiamond address
        bytes32 inputType;
        bytes32 outputType;
        uint256 cost;             // snapshot of agent.quote() at creation
        address payoutAddress;    // snapshot of agent.payoutAddress at creation
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

    event RunStarted(uint256 indexed runId, address indexed user, uint256 tokenId, uint256 deposited);
    event StepRequested(uint256 indexed runId, uint256 stepIndex, address agent, bytes32 requestKey);
    event StepResolved(uint256 indexed runId, uint256 stepIndex, RunStatus runStatus);
    event RunCompleted(uint256 indexed runId, bytes32 finalOutputPointer);
    event RunFailed(uint256 indexed runId, uint256 stepIndex, bytes32 reasonHash);
    event RunCancelled(uint256 indexed runId, uint256 stepIndex);

    /// @notice Start a new run with the given input.
    /// @dev    `msg.value` must be >= totalCost(); excess is refunded immediately.
    function start(uint256 tokenId, bytes32 inputPointer)
        external
        payable
        returns (uint256 runId);

    /// @notice Recovery path: anyone can call this to pull the current step's
    ///         status from the agent and progress the run if the callback was
    ///         missed (revert/OOG/etc).
    function poke(uint256 runId) external;

    /// @notice User or workflow admin can cancel an in-flight run. Cancels
    ///         the in-flight step on the agent; the agent's cancel callback
    ///         then refunds remaining escrow.
    function cancelRun(uint256 runId) external;

    function totalCost() external view returns (uint256);
    function stepCount() external view returns (uint256);
    function getStep(uint256 stepIndex) external view returns (StepSpec memory);
    function getRun(uint256 runId) external view returns (Run memory);
    function getRequestKey(uint256 runId, uint256 stepIndex) external view returns (bytes32);
}
