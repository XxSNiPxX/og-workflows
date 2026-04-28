// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/AgentFactory.sol";
import "../src/AgentRegistry.sol";
import "../src/UserStateINFT.sol";
import "../src/UserStateLedger.sol";
import "../src/oracles/MockERC7857Oracle.sol";

import "../src/facets/DiamondCutFacet.sol";
import "../src/facets/DiamondLoupeFacet.sol";
import "../src/facets/OwnershipFacet.sol";
import "../src/facets/AgentExecutionFacet.sol";
import "../src/facets/AgentPermissionFacet.sol";
import "../src/facets/AgentManifestFacet.sol";
import "../src/facets/AgentAdminFacet.sol";

import "../src/interfaces/IAgentRegistry.sol"; // ✅ needed

contract AgentFactoryTest is Test {
    AgentFactory factory;
    AgentRegistry registry;
    UserStateINFT inft;
    UserStateLedger ledger;
    MockERC7857Oracle oracle;

    address protocolAdmin = address(1);
    address registryAdmin = address(2);
    address devAlice = address(10);
    address devBob = address(11);

    // ---------------------------------------------------------
    // SETUP
    // ---------------------------------------------------------

    function setUp() public {
        oracle = new MockERC7857Oracle(address(this));

        inft = new UserStateINFT(protocolAdmin, address(oracle));
        ledger = new UserStateLedger(address(inft));

        registry = new AgentRegistry(registryAdmin);

        vm.prank(protocolAdmin);
        factory = new AgentFactory(
            address(registry),
            address(inft),
            address(ledger),
            AgentFactory.FacetSet({
                diamondCutFacet: address(new DiamondCutFacet()),
                diamondLoupeFacet: address(new DiamondLoupeFacet()),
                ownershipFacet: address(new OwnershipFacet()),
                agentManifestFacet: address(new AgentManifestFacet()),
                agentPermissionFacet: address(new AgentPermissionFacet()),
                agentExecutionFacet: address(new AgentExecutionFacet()),
                agentAdminFacet: address(new AgentAdminFacet())
            })
        );

        vm.prank(registryAdmin);
        registry.setFactory(address(factory));
    }

    // ---------------------------------------------------------
    // CREATE AGENT
    // ---------------------------------------------------------

    function testCreateAgentHappy() public {
        vm.prank(devAlice);
        (address d, uint256 id) = factory.createAgent(
            AgentFactory.CreateAgentParams({
                name: "x",
                description: "y",
                manifestHash: keccak256("m"),
                inputTypes: _arr(keccak256("type:txt")),
                outputType: keccak256("type:result"),
                costPerRequest: 100,
                payoutAddress: devAlice,
                workflowReady: true
            })
        );

        assertTrue(d != address(0));
        assertEq(id, 1);
    }

    function testOwnershipTransferredToCreator() public {
        vm.prank(devAlice);
        (address d, ) = factory.createAgent(_params(devAlice));

        assertEq(OwnershipFacet(d).owner(), devAlice);
    }

    function testMultipleAgents() public {
        vm.prank(devAlice);
        factory.createAgent(_params(devAlice));

        vm.prank(devBob);
        factory.createAgent(_params(devBob));

        vm.prank(devAlice);
        factory.createAgent(_params(devAlice));

        assertEq(registry.totalAgents(), 3);
    }

    function testRegistryTracksCreator() public {
        vm.prank(devAlice);
        (address d, uint256 id) = factory.createAgent(_params(devAlice));

        // ✅ FIX: struct, not tuple
        IAgentRegistry.AgentRecord memory rec = registry.getAgent(id);

        assertEq(rec.agentAddress, d);
        assertEq(rec.creator, devAlice);
    }

    // ---------------------------------------------------------
    // NEGATIVE CASES
    // ---------------------------------------------------------

    function testZeroPayoutReverts() public {
        vm.prank(devAlice);

        // ⚠️ This will FAIL unless your contract enforces it
        vm.expectRevert();

        factory.createAgent(
            AgentFactory.CreateAgentParams({
                name: "x",
                description: "y",
                manifestHash: keccak256("m"),
                inputTypes: _arr(keccak256("type:txt")),
                outputType: keccak256("type:result"),
                costPerRequest: 100,
                payoutAddress: address(0),
                workflowReady: true
            })
        );
    }

    // ---------------------------------------------------------
    // HELPERS
    // ---------------------------------------------------------

    function _params(
        address payout
    ) internal pure returns (AgentFactory.CreateAgentParams memory p) {
        p = AgentFactory.CreateAgentParams({
            name: "x",
            description: "y",
            manifestHash: keccak256("m"),
            inputTypes: _arr(keccak256("type:txt")),
            outputType: keccak256("type:result"),
            costPerRequest: 100,
            payoutAddress: payout,
            workflowReady: true
        });
    }

    function _arr(bytes32 a) internal pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = a;
    }
}
