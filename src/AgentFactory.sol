// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgentDiamond} from "./AgentDiamond.sol";
import {IDiamond} from "./interfaces/IDiamond.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";

import {DiamondLoupeFacet} from "./facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "./facets/OwnershipFacet.sol";

import {AgentManifestFacet} from "./facets/AgentManifestFacet.sol";
import {AgentPermissionFacet} from "./facets/AgentPermissionFacet.sol";
import {AgentExecutionFacet} from "./facets/AgentExecutionFacet.sol";
import {AgentAdminFacet} from "./facets/AgentAdminFacet.sol";

import {AgentRegistry} from "./AgentRegistry.sol";
import {IAgentRegistry} from "./interfaces/IAgentRegistry.sol";

contract AgentFactory {
    AgentRegistry public immutable registry;

    address public immutable userStateINFT;
    address public immutable userStateLedger;

    // 🔴 CRITICAL ADDITION
    address public immutable workflowFactory;

    // Facet singletons
    address public immutable diamondCutFacet;
    address public immutable diamondLoupeFacet;
    address public immutable ownershipFacet;
    address public immutable agentManifestFacet;
    address public immutable agentPermissionFacet;
    address public immutable agentExecutionFacet;
    address public immutable agentAdminFacet;

    event AgentCreated(uint256 indexed id, address indexed diamond);

    struct FacetSet {
        address diamondCutFacet;
        address diamondLoupeFacet;
        address ownershipFacet;
        address agentManifestFacet;
        address agentPermissionFacet;
        address agentExecutionFacet;
        address agentAdminFacet;
    }

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

    constructor(
        address _registry,
        address _userStateINFT,
        address _userStateLedger,
        address _workflowFactory, // 🔴 ADD
        FacetSet memory f
    ) {
        require(_registry != address(0), "registry=0");
        require(_userStateINFT != address(0), "inft=0");
        require(_userStateLedger != address(0), "ledger=0");
        require(_workflowFactory != address(0), "wf=0");

        registry = AgentRegistry(_registry);
        userStateINFT = _userStateINFT;
        userStateLedger = _userStateLedger;
        workflowFactory = _workflowFactory;

        diamondCutFacet = f.diamondCutFacet;
        diamondLoupeFacet = f.diamondLoupeFacet;
        ownershipFacet = f.ownershipFacet;
        agentManifestFacet = f.agentManifestFacet;
        agentPermissionFacet = f.agentPermissionFacet;
        agentExecutionFacet = f.agentExecutionFacet;
        agentAdminFacet = f.agentAdminFacet;
    }

    function createAgent(
        CreateAgentParams calldata p
    ) external returns (address diamond, uint256 id) {
        diamond = _deployDiamond();

        // STEP 1 — factory becomes admin
        AgentAdminFacet(diamond).setAdmin(address(this));

        // STEP 2 — initialize
        AgentExecutionFacet(diamond).setExecutionConfig(
            userStateINFT,
            userStateLedger
        );

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

        require(
            AgentManifestFacet(diamond).getManifest().createdAt != 0,
            "INIT_FAILED"
        );

        // 🔴 CRITICAL FIX (bind factory permanently)
        AgentPermissionFacet(diamond).setWorkflowFactory(workflowFactory);

        // STEP 3 — give control to user
        AgentAdminFacet(diamond).setAdmin(msg.sender);

        // STEP 4 — register
        id = registry.registerAgent(
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

        emit AgentCreated(id, diamond);
    }

    // --------------------------------------------------
    // DIAMOND DEPLOYMENT
    // --------------------------------------------------

    function _deployDiamond() internal returns (address diamond) {
        diamond = address(new AgentDiamond(address(this), diamondCutFacet));

        IDiamondCut cut = IDiamondCut(diamond);

        _addFacet(cut, diamondLoupeFacet, _loupeSelectors());
        _addFacet(cut, ownershipFacet, _ownershipSelectors());
        _addFacet(cut, agentManifestFacet, _manifestSelectors());
        _addFacet(cut, agentPermissionFacet, _permissionSelectors());
        _addFacet(cut, agentExecutionFacet, _executionSelectors());
        _addFacet(cut, agentAdminFacet, _adminSelectors());
    }

    function _addFacet(
        IDiamondCut cut,
        address facet,
        bytes4[] memory sels
    ) internal {
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);

        cuts[0] = IDiamond.FacetCut({
            facetAddress: facet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: sels
        });

        cut.diamondCut(cuts, address(0), "");
    }

    // --------------------------------------------------
    // SELECTORS
    // --------------------------------------------------

    function _loupeSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = DiamondLoupeFacet.facets.selector;
        s[1] = DiamondLoupeFacet.facetAddresses.selector;
        s[2] = DiamondLoupeFacet.facetAddress.selector;
        s[3] = DiamondLoupeFacet.facetFunctionSelectors.selector;
    }

    function _ownershipSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = OwnershipFacet.owner.selector;
        s[1] = OwnershipFacet.transferOwnership.selector;
    }

    function _manifestSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](14);

        s[0] = bytes4(
            keccak256(
                "initManifest(string,string,bytes32,bytes32[],bytes32,uint256,address,bool)"
            )
        );
        s[1] = bytes4(keccak256("updateMeta(string,string,bytes32)"));
        s[2] = bytes4(keccak256("setPrice(uint256)"));
        s[3] = bytes4(keccak256("setPayoutAddress(address)"));
        s[4] = bytes4(keccak256("setWorkflowReady(bool)"));
        s[5] = bytes4(keccak256("setPaused(bool)"));
        s[6] = bytes4(keccak256("getManifest()"));
        s[7] = bytes4(keccak256("getInputTypes()"));
        s[8] = bytes4(keccak256("getOutputType()"));
        s[9] = bytes4(keccak256("quote()"));
        s[10] = bytes4(keccak256("isPaused()"));
        s[11] = bytes4(keccak256("isWorkflowReady()"));
        s[12] = bytes4(keccak256("supportsInput(bytes32)"));
        s[13] = bytes4(keccak256("payoutAddress()"));
    }

    function _permissionSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = AgentPermissionFacet.setWorkflowFactory.selector;
        s[1] = AgentPermissionFacet.getWorkflowFactory.selector;
        s[2] = AgentPermissionFacet.joinWorkflow.selector;
        s[3] = AgentPermissionFacet.isTrustedCaller.selector;
    }

    function _executionSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](7);

        s[0] = AgentExecutionFacet.setExecutionConfig.selector;
        s[1] = AgentExecutionFacet.getExecutionConfig.selector;

        s[2] = AgentExecutionFacet.request.selector;
        s[3] = AgentExecutionFacet.complete.selector;
        s[4] = AgentExecutionFacet.fail.selector;
        s[5] = AgentExecutionFacet.cancel.selector;

        s[6] = AgentExecutionFacet.getPendingRequests.selector;
    }

    function _adminSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](3);
        s[0] = AgentAdminFacet.admin.selector;
        s[1] = AgentAdminFacet.setAdmin.selector;
        s[2] = AgentAdminFacet.syncToRegistry.selector;
    }
}
