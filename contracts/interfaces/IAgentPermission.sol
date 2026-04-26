// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAgentPermission
/// @notice The subset of AgentPermissionFacet that other contracts call into.
interface IAgentPermission {
    /// @notice Self-add a workflow as a trusted caller. Callable only by the
    ///         registered WorkflowFactory; only succeeds when `workflowReady`
    ///         is true on the agent's manifest.
    function joinWorkflow(address workflow) external;

    function isTrustedCaller(address account) external view returns (bool);

    /// @notice Read-only view of the registered WorkflowFactory address.
    function getWorkflowFactory() external view returns (address);
}
