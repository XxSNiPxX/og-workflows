// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

    function registerAgent(
        RegisterParams calldata p
    ) external returns (uint256);

    function getAgent(
        uint256 agentId
    ) external view returns (AgentRecord memory);

    function getAgentByAddress(
        address agentAddress
    ) external view returns (AgentRecord memory);

    function syncAgent(uint256 agentId) external;
}
