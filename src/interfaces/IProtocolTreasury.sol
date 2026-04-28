// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IProtocolTreasury
/// @notice Per-(workflow, runId) native-token escrow surface.
///         Workflows are registered by `WorkflowFactory` at deploy time; only
///         registered workflows can deposit / release / refund.
interface IProtocolTreasury {
    enum EscrowStatus { NONE, ACTIVE, SETTLED }

    struct Escrow {
        address workflow;
        address payer;
        uint256 runId;
        uint256 deposited;
        uint256 released;
        uint256 refunded;
        EscrowStatus status;
    }

    event WorkflowRegistered(address indexed workflow);
    event Deposited(address indexed workflow, uint256 indexed runId, address indexed payer, uint256 amount);
    event Released(address indexed workflow, uint256 indexed runId, address indexed payee, uint256 amount, uint256 fee);
    event Refunded(address indexed workflow, uint256 indexed runId, address indexed payee, uint256 amount);
    event Settled(address indexed workflow, uint256 indexed runId);

    /// @notice Called by WorkflowFactory at workflow deploy time.
    function registerWorkflow(address workflow) external;

    /// @notice Called by a registered workflow when a user starts a run.
    /// @dev    Must be `payable`; the workflow forwards the user's deposit.
    function deposit(uint256 runId, address payer) external payable;

    /// @notice Release `amount` from the (msg.sender, runId) escrow to `payee`,
    ///         skimming the protocol fee. Only callable by the workflow.
    function releaseTo(uint256 runId, address payee, uint256 amount) external;

    /// @notice Refund `amount` from the (msg.sender, runId) escrow to `recipient`.
    function refundTo(uint256 runId, address recipient, uint256 amount) external;

    /// @notice Mark the (msg.sender, runId) escrow as fully settled. Sweeps any
    ///         remaining balance to `recipient` (typically the user).
    function settle(uint256 runId, address recipient) external;

    function getEscrow(address workflow, uint256 runId) external view returns (Escrow memory);
    function balanceOf(address workflow, uint256 runId) external view returns (uint256);
    function isRegistered(address workflow) external view returns (bool);
}
