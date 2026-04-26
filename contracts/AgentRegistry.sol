// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAgentRegistry} from "./interfaces/IAgentRegistry.sol";
import {LibAgentManifestStorage} from "./libraries/LibAgentManifestStorage.sol";

/// @title AgentRegistry
/// @notice Global, append-only index of every agent diamond deployed via AgentFactory.
///         Mirrors a snapshot of each agent's manifest for O(1) discovery without
///         needing to call into the diamond. The mirror is *eventually consistent*:
///         agents call back via syncAgent (or admin pushes via syncToRegistry on
///         AgentAdminFacet) when their on-chain manifest changes.
contract AgentRegistry is IAgentRegistry {
    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    address public factory;        // only this address may registerAgent
    address public admin;          // governance admin
    bool public registryPaused;    // hard pause for new registrations

    uint256 public nextAgentId;    // 1-indexed
    mapping(uint256 => AgentRecord) internal _agents;
    mapping(address => uint256) public agentIdByAddress;
    mapping(address => uint256[]) internal _agentsByCreator;

    uint256[] internal _allAgentIds;

    // ---------------------------------------------------------------------
    // Events (extends interface events)
    // ---------------------------------------------------------------------

    event FactorySet(address indexed factory);
    event AdminSet(address indexed admin);
    event RegistryPaused(bool paused);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error NotFactory();
    error NotAdmin();
    error ZeroAddress();
    error AlreadyRegistered();
    error UnknownAgent();
    error Paused();

    // ---------------------------------------------------------------------
    // Init
    // ---------------------------------------------------------------------

    constructor(address _admin) {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
        emit AdminSet(_admin);
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    function setFactory(address _factory) external onlyAdmin {
        if (_factory == address(0)) revert ZeroAddress();
        factory = _factory;
        emit FactorySet(_factory);
    }

    function setAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
        emit AdminSet(_admin);
    }

    function setPaused(bool _paused) external onlyAdmin {
        registryPaused = _paused;
        emit RegistryPaused(_paused);
    }

    // ---------------------------------------------------------------------
    // Registration (factory-only)
    // ---------------------------------------------------------------------

    function registerAgent(RegisterParams calldata p)
        external
        override
        returns (uint256 agentId)
    {
        if (msg.sender != factory) revert NotFactory();
        if (registryPaused) revert Paused();
        if (p.agentAddress == address(0)) revert ZeroAddress();
        if (agentIdByAddress[p.agentAddress] != 0) revert AlreadyRegistered();

        agentId = ++nextAgentId;
        AgentRecord storage rec = _agents[agentId];
        rec.agentId = agentId;
        rec.agentAddress = p.agentAddress;
        rec.creator = p.creator;
        rec.admin = p.admin;
        rec.payoutAddress = p.payoutAddress;
        for (uint256 i = 0; i < p.inputTypes.length; i++) {
            rec.inputTypes.push(p.inputTypes[i]);
        }
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
        _agentsByCreator[p.creator].push(agentId);
        _allAgentIds.push(agentId);

        emit AgentRegistered(agentId, p.agentAddress, p.creator);
    }

    // ---------------------------------------------------------------------
    // Sync (anyone can pull a fresh snapshot from the diamond)
    // ---------------------------------------------------------------------

    /// @notice Pull-style refresh. Reads the manifest off the agent diamond
    ///         (via low-level call so we don't hard-depend on the manifest
    ///         facet's interface here) and updates the mirror.
    function syncAgent(uint256 agentId) external override {
        AgentRecord storage rec = _agents[agentId];
        if (rec.agentAddress == address(0)) revert UnknownAgent();

        // Call AgentManifestFacet.getManifest() on the diamond. Using a string
        // signature so we don't depend on a hand-computed selector.
        (bool ok, bytes memory data) = rec.agentAddress.staticcall(
            abi.encodeWithSignature("getManifest()")
        );
        require(ok && data.length > 0, "syncAgent: getManifest failed");

        // Decode as the struct type — a struct return is encoded with one
        // outer offset wrapping the struct body, which `abi.decode((T))` handles
        // correctly.
        LibAgentManifestStorage.AgentManifest memory m = abi.decode(
            data,
            (LibAgentManifestStorage.AgentManifest)
        );

        rec.name = m.name;
        rec.description = m.description;
        rec.manifestHash = m.manifestHash;
        delete rec.inputTypes;
        for (uint256 i = 0; i < m.inputTypes.length; i++) {
            rec.inputTypes.push(m.inputTypes[i]);
        }
        rec.outputType = m.outputType;
        rec.costPerRequest = m.costPerRequest;
        rec.payoutAddress = m.payoutAddress;
        rec.workflowReady = m.workflowReady;
        rec.updatedAt = uint64(block.timestamp);

        emit AgentMetaSynced(agentId, rec.agentAddress);
    }

    /// @notice Admin-only soft-disable; agent itself keeps working but disappears
    ///         from listActiveAgents.
    function setAgentActive(uint256 agentId, bool active_) external onlyAdmin {
        AgentRecord storage rec = _agents[agentId];
        if (rec.agentAddress == address(0)) revert UnknownAgent();
        rec.active = active_;
        rec.updatedAt = uint64(block.timestamp);
        emit AgentActiveSet(agentId, active_);
    }

    // ---------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------

    function getAgent(uint256 agentId) external view returns (AgentRecord memory) {
        return _agents[agentId];
    }

    function getAgentByAddress(address agentAddress) external view returns (AgentRecord memory) {
        return _agents[agentIdByAddress[agentAddress]];
    }

    function listAgentsByCreator(address creator, uint256 cursor, uint256 limit)
        external
        view
        returns (AgentRecord[] memory page, uint256 nextCursor)
    {
        uint256[] storage ids = _agentsByCreator[creator];
        return _paginate(ids, cursor, limit, false);
    }

    function listAllAgents(uint256 cursor, uint256 limit)
        external
        view
        returns (AgentRecord[] memory page, uint256 nextCursor)
    {
        return _paginate(_allAgentIds, cursor, limit, false);
    }

    function listActiveAgents(uint256 cursor, uint256 limit)
        external
        view
        returns (AgentRecord[] memory page, uint256 nextCursor)
    {
        return _paginate(_allAgentIds, cursor, limit, true);
    }

    function totalAgents() external view returns (uint256) {
        return _allAgentIds.length;
    }

    function _paginate(
        uint256[] storage ids,
        uint256 cursor,
        uint256 limit,
        bool activeOnly
    ) internal view returns (AgentRecord[] memory page, uint256 nextCursor) {
        if (cursor >= ids.length) return (new AgentRecord[](0), ids.length);
        uint256 end = cursor + limit;
        if (end > ids.length) end = ids.length;

        // First pass: count matches if filtering
        uint256 keep = end - cursor;
        if (activeOnly) {
            keep = 0;
            for (uint256 i = cursor; i < end; i++) {
                if (_agents[ids[i]].active) keep++;
            }
        }

        page = new AgentRecord[](keep);
        uint256 j;
        for (uint256 i = cursor; i < end; i++) {
            AgentRecord storage rec = _agents[ids[i]];
            if (activeOnly && !rec.active) continue;
            page[j++] = rec;
        }
        nextCursor = end;
    }
}
