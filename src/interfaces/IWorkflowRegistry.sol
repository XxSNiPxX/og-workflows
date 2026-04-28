// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IWorkflowRegistry
/// @notice Global, append-only index of every workflow deployed via WorkflowFactory.
interface IWorkflowRegistry {
    struct WorkflowRecord {
        uint256 workflowId;
        address workflowAddress;
        address creator;
        bytes32 inputType;       // type the workflow expects to start with
        bytes32 outputType;      // type the workflow produces at the end
        uint256 totalCost;       // snapshot sum of step costs at creation
        uint256 stepCount;
        bool active;
        uint64 createdAt;
        string name;
        string description;
    }

    struct RegisterParams {
        address workflowAddress;
        address creator;
        bytes32 inputType;
        bytes32 outputType;
        uint256 totalCost;
        uint256 stepCount;
        string name;
        string description;
    }

    event WorkflowRegistered(
        uint256 indexed workflowId,
        address indexed workflowAddress,
        address indexed creator
    );
    event WorkflowActiveSet(uint256 indexed workflowId, bool active);

    /// @notice Called by WorkflowFactory immediately after deploying a WorkflowInstance.
    function registerWorkflow(RegisterParams calldata p) external returns (uint256 workflowId);
}
