// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/AgentRegistry.sol";
import "../src/AgentFactory.sol";
import "../src/UserStateINFT.sol";
import "../src/UserStateLedger.sol";
import "../src/oracles/MockERC7857Oracle.sol";
import "../src/interfaces/IAgentRegistry.sol";

contract AgentRegistryTest is Test {
    AgentRegistry registry;
    AgentFactory factory;
    UserStateINFT inft;
    UserStateLedger ledger;
    MockERC7857Oracle oracle;

    address registryAdmin = address(1);
    address protocolAdmin = address(2);
    address oracleAdmin = address(3);

    address devAlice = address(10);
    address devBob = address(11);
    address other = address(99);

    function H(string memory s) internal pure returns (bytes32) {
        return keccak256(bytes(s));
    }

    // =============================================================
    // SETUP
    // =============================================================

    function setUp() public {
        vm.prank(oracleAdmin);
        oracle = new MockERC7857Oracle(oracleAdmin);

        vm.prank(protocolAdmin);
        inft = new UserStateINFT(protocolAdmin, address(oracle));

        ledger = new UserStateLedger(address(inft));

        vm.prank(registryAdmin);
        registry = new AgentRegistry(registryAdmin);

        vm.prank(protocolAdmin);
        factory = new AgentFactory(
            address(registry),
            address(inft),
            address(ledger),
            AgentFactory.FacetSet({
                diamondCutFacet: address(0),
                diamondLoupeFacet: address(0),
                ownershipFacet: address(0),
                agentManifestFacet: address(0),
                agentPermissionFacet: address(0),
                agentExecutionFacet: address(0),
                agentAdminFacet: address(0)
            })
        );

        vm.prank(registryAdmin);
        registry.setFactory(address(factory));
    }

    // =============================================================
    // CONFIG
    // =============================================================

    function testConstructorRejectsZero() public {
        vm.expectRevert(AgentRegistry.ZeroAddress.selector);
        new AgentRegistry(address(0));
    }

    function testSetFactoryGuards() public {
        vm.expectRevert(AgentRegistry.NotAdmin.selector);
        vm.prank(other);
        registry.setFactory(other);

        vm.expectRevert(AgentRegistry.ZeroAddress.selector);
        vm.prank(registryAdmin);
        registry.setFactory(address(0));
    }

    function testSetAdmin() public {
        vm.expectRevert(AgentRegistry.NotAdmin.selector);
        vm.prank(other);
        registry.setAdmin(other);

        vm.prank(registryAdmin);
        registry.setAdmin(other);

        assertEq(registry.admin(), other);
    }

    function testSetPaused() public {
        vm.expectRevert(AgentRegistry.NotAdmin.selector);
        vm.prank(other);
        registry.setPaused(true);

        vm.prank(registryAdmin);
        registry.setPaused(true);

        assertTrue(registry.registryPaused());
    }

    // =============================================================
    // FACTORY-ONLY REGISTER
    // =============================================================

    function testNonFactoryReverts() public {
        vm.expectRevert(AgentRegistry.NotFactory.selector);

        vm.prank(other);

        IAgentRegistry.RegisterParams memory p = IAgentRegistry.RegisterParams({
            agentAddress: address(1),
            creator: other,
            admin: other,
            payoutAddress: other,
            inputTypes: _arr(H("type:txt")),
            outputType: H("type:result"),
            costPerRequest: 100,
            workflowReady: true,
            name: "x",
            description: "y",
            manifestHash: H("m")
        });

        registry.registerAgent(p);
    }

    function testRegisterViaFactory() public {
        (address diamond, uint256 id) = _createAgent(devAlice);

        IAgentRegistry.AgentRecord memory rec = registry.getAgent(id);

        assertEq(rec.agentAddress, diamond);
        assertEq(rec.creator, devAlice);
        assertEq(rec.outputType, H("type:result"));
        assertTrue(rec.active);
    }

    function testReverseLookup() public {
        (address diamond, uint256 id) = _createAgent(devAlice);
        assertEq(registry.agentIdByAddress(diamond), id);
    }

    function testPausedRejectsCreate() public {
        vm.prank(registryAdmin);
        registry.setPaused(true);

        IAgentRegistry.RegisterParams memory p =
            IAgentRegistry.RegisterParams({
                agentAddress: address(123),
                creator: devAlice,
                admin: devAlice,
                payoutAddress: devAlice,
                inputTypes: _arr(H("type:txt")),
                outputType: H("type:result"),
                costPerRequest: 100,
                workflowReady: true,
                name: "agent",
                description: "test",
                manifestHash: H("m")
            });

        vm.expectRevert(AgentRegistry.Paused.selector);

        vm.prank(address(factory));
        registry.registerAgent(p);
    }

    // =============================================================
    // LISTING
    // =============================================================

    function testListAllAgents() public {
        _createN(3);

        (IAgentRegistry.AgentRecord[] memory page, uint256 cursor) = registry
            .listAllAgents(0, 100);

        assertEq(page.length, 3);
        assertEq(cursor, 3);
    }

    function testListByCreator() public {
        _createAgent(devAlice);
        _createAgent(devBob);
        _createAgent(devAlice);

        (IAgentRegistry.AgentRecord[] memory a, ) = registry
            .listAgentsByCreator(devAlice, 0, 100);

        (IAgentRegistry.AgentRecord[] memory b, ) = registry
            .listAgentsByCreator(devBob, 0, 100);

        assertEq(a.length, 2);
        assertEq(b.length, 1);
    }

    function testTotalAgents() public {
        assertEq(registry.totalAgents(), 0);

        _createN(2);

        assertEq(registry.totalAgents(), 2);
    }

    function testListActive() public {
        (, uint256 id1) = _createAgent(devAlice);
        (, uint256 id2) = _createAgent(devAlice);
        (, uint256 id3) = _createAgent(devAlice);

        vm.prank(registryAdmin);
        registry.setAgentActive(id2, false);

        (IAgentRegistry.AgentRecord[] memory page, ) = registry
            .listActiveAgents(0, 100);

        assertEq(page.length, 2);
    }

    // =============================================================
    // ACTIVE FLAG
    // =============================================================

    function testSetAgentActive() public {
        (, uint256 id) = _createAgent(devAlice);

        vm.expectRevert(AgentRegistry.NotAdmin.selector);
        vm.prank(other);
        registry.setAgentActive(id, false);

        vm.prank(registryAdmin);
        registry.setAgentActive(id, false);

        IAgentRegistry.AgentRecord memory rec = registry.getAgent(id);
        assertFalse(rec.active);
    }

    function testSetAgentActiveUnknown() public {
        vm.expectRevert(AgentRegistry.UnknownAgent.selector);

        vm.prank(registryAdmin);
        registry.setAgentActive(999, false);
    }

    // =============================================================
    // SYNC
    // =============================================================

    function testSyncAgent() public {
        (, uint256 id) = _createAgent(devAlice);

        vm.expectRevert("syncAgent: getManifest failed");

        vm.prank(other);
        registry.syncAgent(id);
    }

    function testSyncUnknown() public {
        vm.expectRevert(AgentRegistry.UnknownAgent.selector);

        vm.prank(other);
        registry.syncAgent(999);
    }

    // =============================================================
    // HELPERS
    // =============================================================

    function _createN(uint256 n) internal {
        for (uint256 i; i < n; i++) {
            _createAgent(devAlice);
        }
    }

    uint256 internal nonce;

    function _createAgent(
        address dev
    ) internal returns (address diamond, uint256 id) {
        diamond = address(uint160(++nonce)); // simple + deterministic

        IAgentRegistry.RegisterParams memory p =
            IAgentRegistry.RegisterParams({
                agentAddress: diamond,
                creator: dev,
                admin: dev,
                payoutAddress: dev,
                inputTypes: _arr(H("type:txt")),
                outputType: H("type:result"),
                costPerRequest: 100,
                workflowReady: true,
                name: "agent",
                description: "test",
                manifestHash: H("m")
            });

        vm.prank(address(factory));
        id = registry.registerAgent(p);
    }

    function _defaultParams()
        internal
        view
        returns (AgentFactory.CreateAgentParams memory)
    {
        return
            AgentFactory.CreateAgentParams({
                name: "agent",
                description: "test",
                manifestHash: H("m"),
                inputTypes: _arr(H("type:txt")),
                outputType: H("type:result"),
                costPerRequest: 100,
                payoutAddress: devAlice,
                workflowReady: true
            });
    }

    function _arr(bytes32 a) internal pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = a;
    }
}
