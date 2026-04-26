// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgentDiamond} from "./AgentDiamond.sol";
import {InitialFaucets} from "./AgentDiamondShared.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";
import {IDiamond} from "./interfaces/IDiamond.sol";

import {DiamondCutFacet} from "./facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "./facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "./facets/OwnershipFacet.sol";
import {FacetRegistryFacet} from "./facets/FacetRegistryFacet.sol";

import {AgentManifestFacet} from "./facets/AgentManifestFacet.sol";
import {AgentPermissionFacet} from "./facets/AgentPermissionFacet.sol";
import {AgentExecutionFacet} from "./facets/AgentExecutionFacet.sol";
import {AgentAdminFacet} from "./facets/AgentAdminFacet.sol";

import {AgentRegistry} from "./AgentRegistry.sol";
import {IAgentRegistry} from "./interfaces/IAgentRegistry.sol";

/// @title AgentFactory
/// @notice Deploys a new AgentDiamond per agent, wires every required facet,
///         calls initManifest, sets the execution config, and registers the
///         agent in the global AgentRegistry — all in one transaction.
///
///         Flow:
///           1. Deploy fresh facet singletons (one set per agent — keeps
///              storage layouts isolated per diamond and avoids any shared-state
///              pitfalls; matches the existing CoreGameFactory pattern).
///           2. Build parallel FacetCut[] and string[] arrays.
///           3. Deploy AgentDiamond with msg.sender as initial owner.
///           4. As factory we are NOT the owner of the new diamond — so we
///              must call configuration methods *before* transferring control.
///              We do this by being temporary owner first, then transferring
///              to the developer at the end.
contract AgentFactory {
    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    AgentRegistry public immutable registry;

    // We deploy these standard facet singletons once at factory-init time
    // and reuse them across every agent. Domain facets *also* are reused —
    // they are stateless contracts; per-diamond state lives in the diamond
    // via diamond storage. This is the standard EIP-2535 pattern (different
    // from CoreGameFactory which redeployed facets every call).
    DiamondCutFacet public immutable diamondCutFacet;
    DiamondLoupeFacet public immutable diamondLoupeFacet;
    OwnershipFacet public immutable ownershipFacet;
    FacetRegistryFacet public immutable facetRegistryFacet;
    AgentManifestFacet public immutable agentManifestFacet;
    AgentPermissionFacet public immutable agentPermissionFacet;
    AgentExecutionFacet public immutable agentExecutionFacet;
    AgentAdminFacet public immutable agentAdminFacet;

    // protocol-level addresses passed into every new agent's execution config
    address public userStateINFT;
    address public userStateLedger;
    address public protocolAdmin;

    // factory-side index (registry has its own; this is a convenience)
    mapping(address => address[]) public developerToAgents;
    address[] public allAgents;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event AgentCreated(
        uint256 indexed agentId,
        address indexed agentDiamond,
        address indexed creator
    );
    event ProtocolAddressesUpdated(address userStateINFT, address userStateLedger);
    event ProtocolAdminSet(address admin);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error NotProtocolAdmin();
    error ZeroAddress();

    // ---------------------------------------------------------------------
    // Init
    // ---------------------------------------------------------------------

    constructor(address _registry, address _userStateINFT, address _userStateLedger, address _protocolAdmin) {
        if (_registry == address(0)) revert ZeroAddress();
        if (_protocolAdmin == address(0)) revert ZeroAddress();
        registry = AgentRegistry(_registry);
        userStateINFT = _userStateINFT;
        userStateLedger = _userStateLedger;
        protocolAdmin = _protocolAdmin;

        diamondCutFacet     = new DiamondCutFacet();
        diamondLoupeFacet   = new DiamondLoupeFacet();
        ownershipFacet      = new OwnershipFacet();
        facetRegistryFacet  = new FacetRegistryFacet();
        agentManifestFacet  = new AgentManifestFacet();
        agentPermissionFacet = new AgentPermissionFacet();
        agentExecutionFacet = new AgentExecutionFacet();
        agentAdminFacet     = new AgentAdminFacet();

        emit ProtocolAdminSet(_protocolAdmin);
        emit ProtocolAddressesUpdated(_userStateINFT, _userStateLedger);
    }

    modifier onlyProtocolAdmin() {
        if (msg.sender != protocolAdmin) revert NotProtocolAdmin();
        _;
    }

    function setProtocolAddresses(address _inft, address _ledger) external onlyProtocolAdmin {
        userStateINFT = _inft;
        userStateLedger = _ledger;
        emit ProtocolAddressesUpdated(_inft, _ledger);
    }

    function setProtocolAdmin(address _admin) external onlyProtocolAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        protocolAdmin = _admin;
        emit ProtocolAdminSet(_admin);
    }

    // ---------------------------------------------------------------------
    // createAgent — single-call deploy + init + register
    // ---------------------------------------------------------------------

    struct CreateAgentParams {
        string name;
        string description;
        bytes32 manifestHash;
        bytes32[] inputTypes;
        bytes32 outputType;
        uint256 costPerRequest;
        address payoutAddress;
        bool workflowReady;
    }

    function createAgent(CreateAgentParams calldata p)
        external
        returns (address diamond, uint256 agentId)
    {
        if (p.payoutAddress == address(0)) revert ZeroAddress();

        // 1+2. Build cuts and deploy diamond with the FACTORY as initial owner
        //      so we can configure the diamond before handing over to the dev.
        diamond = _deployDiamond();

        // 3. Initialize the manifest via the diamond's fallback to AgentManifestFacet.
        _initManifest(diamond, p);

        // 4. Wire protocol addresses for the execution facet.
        AgentExecutionFacet(diamond).setExecutionConfig(userStateINFT, userStateLedger);

        // 5. Register in global registry while we still own the diamond.
        agentId = _register(diamond, p);

        // 6. Hand ownership of the diamond to the developer.
        AgentDiamond(payable(diamond)).transferOwnership(msg.sender);

        // 7. Bookkeeping
        developerToAgents[msg.sender].push(diamond);
        allAgents.push(diamond);

        emit AgentCreated(agentId, diamond, msg.sender);
    }

    function _deployDiamond() internal returns (address diamond) {
        IDiamondCut.FacetCut[] memory cuts = _buildCuts();
        InitialFaucets[] memory initial = _buildInitialFaucets();
        AgentDiamond d = new AgentDiamond(address(this), initial, cuts);
        diamond = address(d);
    }

    function _initManifest(address diamond, CreateAgentParams calldata p) internal {
        AgentManifestFacet(diamond).initManifest(
            p.name,
            p.description,
            p.manifestHash,
            p.inputTypes,
            p.outputType,
            p.costPerRequest,
            p.payoutAddress,
            p.workflowReady
        );
    }

    function _register(address diamond, CreateAgentParams calldata p) internal returns (uint256) {
        return registry.registerAgent(
            IAgentRegistry.RegisterParams({
                agentAddress: diamond,
                creator: msg.sender,
                admin: msg.sender,
                payoutAddress: p.payoutAddress,
                inputTypes: p.inputTypes,
                outputType: p.outputType,
                costPerRequest: p.costPerRequest,
                workflowReady: p.workflowReady,
                name: p.name,
                description: p.description,
                manifestHash: p.manifestHash
            })
        );
    }

    // ---------------------------------------------------------------------
    // Internal builders
    // ---------------------------------------------------------------------

    function _buildInitialFaucets() internal view returns (InitialFaucets[] memory initial) {
        initial = new InitialFaucets[](8);
        initial[0] = InitialFaucets("DiamondCutFacet",      address(diamondCutFacet));
        initial[1] = InitialFaucets("DiamondLoupeFacet",    address(diamondLoupeFacet));
        initial[2] = InitialFaucets("OwnershipFacet",       address(ownershipFacet));
        initial[3] = InitialFaucets("FacetRegistryFacet",   address(facetRegistryFacet));
        initial[4] = InitialFaucets("AgentManifestFacet",   address(agentManifestFacet));
        initial[5] = InitialFaucets("AgentPermissionFacet", address(agentPermissionFacet));
        initial[6] = InitialFaucets("AgentExecutionFacet",  address(agentExecutionFacet));
        initial[7] = InitialFaucets("AgentAdminFacet",      address(agentAdminFacet));
    }

    function _buildCuts() internal view returns (IDiamondCut.FacetCut[] memory cuts) {
        cuts = new IDiamondCut.FacetCut[](8);

        cuts[0] = IDiamond.FacetCut({
            facetAddress: address(diamondCutFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: _diamondCutSelectors()
        });
        cuts[1] = IDiamond.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: _diamondLoupeSelectors()
        });
        cuts[2] = IDiamond.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: _ownershipSelectors()
        });
        cuts[3] = IDiamond.FacetCut({
            facetAddress: address(facetRegistryFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: _facetRegistrySelectors()
        });
        cuts[4] = IDiamond.FacetCut({
            facetAddress: address(agentManifestFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: _agentManifestSelectors()
        });
        cuts[5] = IDiamond.FacetCut({
            facetAddress: address(agentPermissionFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: _agentPermissionSelectors()
        });
        cuts[6] = IDiamond.FacetCut({
            facetAddress: address(agentExecutionFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: _agentExecutionSelectors()
        });
        cuts[7] = IDiamond.FacetCut({
            facetAddress: address(agentAdminFacet),
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: _agentAdminSelectors()
        });
    }

    // ---------------------------------------------------------------------
    // Selector tables — kept here so anyone reading the factory can audit
    // exactly which surface each agent diamond exposes. Each entry is the
    // 4-byte function selector of the corresponding facet function.
    // ---------------------------------------------------------------------

    function _diamondCutSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = DiamondCutFacet.diamondCut.selector;
        s[1] = DiamondCutFacet.diamondCutWithName.selector;
    }

    function _diamondLoupeSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](5);
        s[0] = DiamondLoupeFacet.facets.selector;
        s[1] = DiamondLoupeFacet.facetFunctionSelectors.selector;
        s[2] = DiamondLoupeFacet.facetAddresses.selector;
        s[3] = DiamondLoupeFacet.facetAddress.selector;
        s[4] = DiamondLoupeFacet.supportsInterface.selector;
    }

    function _ownershipSelectors() internal pure returns (bytes4[] memory s) {
        // NB: AgentDiamond also defines owner() / transferOwnership() / supportsInterface()
        // *directly* on the diamond contract (mirroring CoreGameDiamond). Those direct
        // implementations win over any facet-routed call because the fallback only fires
        // if the function isn't found on the contract itself. So OwnershipFacet's owner()
        // and transferOwnership() are technically unreachable in this layout — we still
        // attach them for EIP-2535 conformance and so a future diamond shell *without*
        // the inline implementations stays functional.
        s = new bytes4[](2);
        s[0] = OwnershipFacet.owner.selector;
        s[1] = OwnershipFacet.transferOwnership.selector;
    }

    function _facetRegistrySelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](3);
        s[0] = FacetRegistryFacet.getFacetName.selector;
        s[1] = FacetRegistryFacet.getFacetAddress.selector;
        s[2] = FacetRegistryFacet.getAllFacets.selector;
    }

    function _agentManifestSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](13);
        s[0]  = AgentManifestFacet.initManifest.selector;
        s[1]  = AgentManifestFacet.updateMeta.selector;
        s[2]  = AgentManifestFacet.setPrice.selector;
        s[3]  = AgentManifestFacet.setPayoutAddress.selector;
        s[4]  = AgentManifestFacet.setWorkflowReady.selector;
        s[5]  = AgentManifestFacet.setPaused.selector;
        s[6]  = AgentManifestFacet.getManifest.selector;
        s[7]  = AgentManifestFacet.getInputTypes.selector;
        s[8]  = AgentManifestFacet.getOutputType.selector;
        s[9]  = AgentManifestFacet.quote.selector;
        s[10] = AgentManifestFacet.isPaused.selector;
        s[11] = AgentManifestFacet.isWorkflowReady.selector;
        s[12] = AgentManifestFacet.supportsInput.selector;
    }

    function _agentPermissionSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](6);
        s[0] = AgentPermissionFacet.setWorker.selector;
        s[1] = AgentPermissionFacet.isWorker.selector;
        s[2] = AgentPermissionFacet.getWorkers.selector;
        s[3] = AgentPermissionFacet.setTrustedCaller.selector;
        s[4] = AgentPermissionFacet.isTrustedCaller.selector;
        s[5] = AgentPermissionFacet.getTrustedCallers.selector;
    }

    function _agentExecutionSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](12);
        s[0]  = AgentExecutionFacet.setExecutionConfig.selector;
        s[1]  = AgentExecutionFacet.getExecutionConfig.selector;
        s[2]  = AgentExecutionFacet.request.selector;
        s[3]  = AgentExecutionFacet.userRequest.selector;
        s[4]  = AgentExecutionFacet.acknowledge.selector;
        s[5]  = AgentExecutionFacet.complete.selector;
        s[6]  = AgentExecutionFacet.fail.selector;
        s[7]  = AgentExecutionFacet.cancel.selector;
        s[8]  = AgentExecutionFacet.getRequest.selector;
        s[9]  = AgentExecutionFacet.getRequestKeysForUser.selector;
        s[10] = AgentExecutionFacet.getAllRequestKeys.selector;
        s[11] = AgentExecutionFacet.totalRequests.selector;
    }

    function _agentAdminSelectors() internal pure returns (bytes4[] memory s) {
        // NB: AgentAdminFacet.admin() collides with OwnershipFacet.owner() ONLY semantically
        // — they're different selectors. AgentAdminFacet.setAdmin() is a separate selector
        // from transferOwnership() and exists for the admin-flavored event.
        s = new bytes4[](3);
        s[0] = AgentAdminFacet.admin.selector;
        s[1] = AgentAdminFacet.setAdmin.selector;
        s[2] = AgentAdminFacet.syncToRegistry.selector;
    }

    // ---------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------

    function getAgentsByDeveloper(address dev) external view returns (address[] memory) {
        return developerToAgents[dev];
    }

    function getAllAgents() external view returns (address[] memory) {
        return allAgents;
    }

    function totalAgents() external view returns (uint256) {
        return allAgents.length;
    }

    /// @notice Excludes getRequestKeysForUser and totalRequests from a hot-path estimate.
    ///         Cheap helper for off-chain estimators.
    function estimateAgentDeployCost() external pure returns (uint256 facetCount) {
        return 8;
    }
}
