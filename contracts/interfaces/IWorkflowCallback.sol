// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IWorkflowCallback
/// @notice Hook agents call into the workflow contract after a step reaches a
///         terminal state (completed / failed / cancelled). All callbacks are
///         invoked from `AgentExecutionFacet` via try/catch — a reverting
///         callback must not lock the worker out of getting their step recorded.
///
///         A workflow that misses a callback (revert, OOG, etc.) can recover
///         by having anyone call `WorkflowInstance.poke(runId)`, which reads
///         the current step's status on the agent and progresses accordingly.
interface IWorkflowCallback {
    /// @notice Called after the agent has stamped the request as COMPLETED
    ///         and written the output to the user's ledger.
    function onStepCompleted(
        uint256 runId,
        uint256 stepIndex,
        bytes32 outputPointer,
        bytes32 outputType,
        bytes32 outputHash
    ) external;

    /// @notice Called after the agent has stamped the request as FAILED.
    function onStepFailed(
        uint256 runId,
        uint256 stepIndex,
        bytes32 reasonHash
    ) external;

    /// @notice Called after the agent has stamped the request as CANCELLED.
    function onStepCancelled(
        uint256 runId,
        uint256 stepIndex
    ) external;
}
