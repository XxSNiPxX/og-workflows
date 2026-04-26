// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAgentManifest
/// @notice The subset of AgentManifestFacet that other contracts read from.
///         Used by WorkflowFactory to validate workflow definitions and
///         snapshot per-step prices at workflow creation time.
interface IAgentManifest {
    function quote() external view returns (uint256);
    function getOutputType() external view returns (bytes32);
    function isWorkflowReady() external view returns (bool);
    function isPaused() external view returns (bool);
    function supportsInput(bytes32 inputType) external view returns (bool);
}
