// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAgentRegistry} from "./interfaces/IAgentRegistry.sol";
import {LibAgentManifestStorage} from "./libraries/LibAgentManifestStorage.sol";

contract AgentRegistry is IAgentRegistry {
    address public factory;
    address public admin;

    uint256 public nextAgentId;

    mapping(uint256 => AgentRecord) internal _agents;
    mapping(address => uint256) public agentIdByAddress;

    // ✅ NEW: enumeration
    uint256[] public allAgentIds;

    error NotFactory();
    error ZeroAddress();
    error AlreadyRegistered();

    constructor(address _admin) {
        admin = _admin;
    }

    function setFactory(address _factory) external {
        factory = _factory;
    }

    function registerAgent(
        RegisterParams calldata p
    ) external override returns (uint256 agentId) {
        if (msg.sender != factory) revert NotFactory();
        if (p.agentAddress == address(0)) revert ZeroAddress();
        if (agentIdByAddress[p.agentAddress] != 0) revert AlreadyRegistered();

        agentId = ++nextAgentId;

        AgentRecord storage rec = _agents[agentId];

        rec.agentId = agentId;
        rec.agentAddress = p.agentAddress;
        rec.creator = p.creator;
        rec.admin = p.admin;
        rec.payoutAddress = p.payoutAddress;

        rec.inputTypes = p.inputTypes;
        rec.outputType = p.outputType;
        rec.costPerRequest = p.costPerRequest;
        rec.workflowReady = p.workflowReady;
        rec.active = true;

        rec.createdAt = uint64(block.timestamp);
        rec.updatedAt = uint64(block.timestamp);

        rec.name = p.name;
        rec.description = p.description;
        rec.manifestHash = p.manifestHash;

        agentIdByAddress[p.agentAddress] = agentId;

        // ✅ track all agents
        allAgentIds.push(agentId);
    }

    function getAgent(
        uint256 agentId
    ) external view override returns (IAgentRegistry.AgentRecord memory) {
        return _agents[agentId];
    }

    function getAgentByAddress(
        address agentAddress
    ) external view override returns (IAgentRegistry.AgentRecord memory) {
        return _agents[agentIdByAddress[agentAddress]];
    }

    // ✅ NEW: list all agents
    function getAllAgents()
        external
        view
        returns (IAgentRegistry.AgentRecord[] memory)
    {
        uint256 len = allAgentIds.length;
        IAgentRegistry.AgentRecord[]
            memory out = new IAgentRegistry.AgentRecord[](len);

        for (uint256 i = 0; i < len; i++) {
            out[i] = _agents[allAgentIds[i]];
        }

        return out;
    }

    function syncAgent(uint256 agentId) external override {
        AgentRecord storage rec = _agents[agentId];

        (bool ok, bytes memory data) = rec.agentAddress.staticcall(
            abi.encodeWithSignature("getManifest()")
        );

        require(ok);

        LibAgentManifestStorage.AgentManifest memory m = abi.decode(
            data,
            (LibAgentManifestStorage.AgentManifest)
        );

        rec.workflowReady = m.workflowReady;
        rec.payoutAddress = m.payoutAddress;
        rec.updatedAt = uint64(block.timestamp);
    }
}
