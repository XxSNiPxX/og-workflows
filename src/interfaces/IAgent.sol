// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAgent (Option B canonical interface)
interface IAgent {
    // -------- Validation --------
    function isWorkflowReady() external view returns (bool);

    function isPaused() external view returns (bool);

    function supportsInput(bytes32 t) external view returns (bool);

    function getOutputType() external view returns (bytes32);

    // -------- Pricing --------
    function quote() external view returns (uint256);

    // -------- Payout --------
    function payoutAddress() external view returns (address);

    // -------- Permissions (minimal needed by factory) --------
    function joinWorkflow(address workflow) external;
}
