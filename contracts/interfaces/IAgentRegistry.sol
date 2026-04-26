// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAgentRegistry
/// @notice Global, append-only index of every agent diamond deployed via AgentFactory.
interface IAgentRegistry {
    struct AgentRecord {
        uint256 agentId;
        address agentAddress;
        address creator;
        address admin;
        address payoutAddress;
        bytes32[] inputTypes;
        bytes32 outputType;
        uint256 costPerRequest;
        bool workflowReady;
        bool active;
        uint64 createdAt;
        uint64 updatedAt;
        string name;
        string description;
        bytes32 manifestHash;
    }

    event AgentRegistered(
        uint256 indexed agentId,
        address indexed agentAddress,
        address indexed creator
    );

    event AgentMetaSynced(
        uint256 indexed agentId,
        address indexed agentAddress
    );

    event AgentActiveSet(uint256 indexed agentId, bool active);

    /// @notice Parameters for registerAgent — bundled into a struct to avoid
    ///         stack-too-deep at the registration call site.
    struct RegisterParams {
        address agentAddress;
        address creator;
        address admin;
        address payoutAddress;
        bytes32[] inputTypes;
        bytes32 outputType;
        uint256 costPerRequest;
        bool workflowReady;
        string name;
        string description;
        bytes32 manifestHash;
    }

    /// @notice Called by AgentFactory immediately after deploying an AgentDiamond.
    function registerAgent(RegisterParams calldata p) external returns (uint256 agentId);

    /// @notice Pull-style refresh: registry reads from the agent diamond and
    ///         updates its mirrored manifest fields. Callable by anyone.
    function syncAgent(uint256 agentId) external;
}
