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
import "../src/facets/AgentAdminFacet.sol";
import "../src/facets/AgentPermissionFacet.sol";
import "../src/facets/AgentManifestFacet.sol";

contract AgentPermissionFacetTest is Test {
    AgentFactory factory;
    AgentRegistry registry;
    UserStateINFT inft;
    UserStateLedger ledger;
    MockERC7857Oracle oracle;

    address registryAdmin = address(1);
    address protocolAdmin = address(2);
    address oracleAdmin = address(3);

    address devAlice = address(10);
    address worker1 = address(20);
    address user1 = address(30);
    address other = address(99);

    address ZERO = address(0);

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

    // =============================================================
    // HELPERS
    // =============================================================

    function _createAgent() internal returns (address diamond, uint256 id) {
        vm.prank(devAlice);
        (diamond, id) = factory.createAgent(
            AgentFactory.CreateAgentParams({
                name: "A",
                description: "B",
                manifestHash: keccak256("m"),
                inputTypes: _arr(keccak256("type")),
                outputType: keccak256("out"),
                costPerRequest: 100,
                payoutAddress: devAlice,
                workflowReady: true
            })
        );
    }

    function _arr(bytes32 a) internal pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = a;
    }

    function _perm(
        address diamond
    ) internal pure returns (AgentPermissionFacet) {
        return AgentPermissionFacet(diamond);
    }

    // =============================================================
    // WORKERS
    // =============================================================

    function testSetWorkerAddRemove() public {
        (address d, ) = _createAgent();

        assertFalse(_perm(d).isWorker(worker1));

        vm.prank(devAlice);
        _perm(d).setWorker(worker1, true);

        assertTrue(_perm(d).isWorker(worker1));

        address[] memory list = _perm(d).getWorkers();
        assertEq(list.length, 1);
        assertEq(list[0], worker1);

        vm.prank(devAlice);
        _perm(d).setWorker(worker1, false);

        assertFalse(_perm(d).isWorker(worker1));
        assertEq(_perm(d).getWorkers().length, 0);
    }

    function testSetWorkerNonAdminReverts() public {
        (address d, ) = _createAgent();

        vm.expectRevert();
        vm.prank(other);
        _perm(d).setWorker(worker1, true);
    }

    function testSetWorkerZeroReverts() public {
        (address d, ) = _createAgent();

        vm.expectRevert(AgentPermissionFacet.ZeroAddress.selector);
        vm.prank(devAlice);
        _perm(d).setWorker(ZERO, true);
    }

    function testSetWorkerIdempotentTrue() public {
        (address d, ) = _createAgent();

        vm.prank(devAlice);
        _perm(d).setWorker(worker1, true);

        vm.prank(devAlice);
        _perm(d).setWorker(worker1, true);

        assertEq(_perm(d).getWorkers().length, 1);
    }

    function testSetWorkerIdempotentFalse() public {
        (address d, ) = _createAgent();

        vm.prank(devAlice);
        _perm(d).setWorker(worker1, false);

        assertEq(_perm(d).getWorkers().length, 0);
    }

    // =============================================================
    // TRUSTED CALLERS
    // =============================================================

    function testTrustedCallerAddRemove() public {
        (address d, ) = _createAgent();

        assertFalse(_perm(d).isTrustedCaller(user1));

        vm.prank(devAlice);
        _perm(d).setTrustedCaller(user1, true);

        assertTrue(_perm(d).isTrustedCaller(user1));

        vm.prank(devAlice);
        _perm(d).setTrustedCaller(user1, false);

        assertFalse(_perm(d).isTrustedCaller(user1));
    }

    function testAdminIsTrustedCaller() public {
        (address d, ) = _createAgent();

        assertTrue(_perm(d).isTrustedCaller(devAlice));
    }

    function testTrustedCallerNonAdminReverts() public {
        (address d, ) = _createAgent();

        vm.expectRevert();
        vm.prank(other);
        _perm(d).setTrustedCaller(user1, true);
    }

    function testTrustedCallerZeroReverts() public {
        (address d, ) = _createAgent();

        vm.expectRevert(AgentPermissionFacet.ZeroAddress.selector);
        vm.prank(devAlice);
        _perm(d).setTrustedCaller(ZERO, true);
    }

    // =============================================================
    // WORKFLOW
    // =============================================================

    function testSetWorkflowFactoryAdminOnly() public {
        (address d, ) = _createAgent();

        vm.expectRevert();
        vm.prank(other);
        _perm(d).setWorkflowFactory(other);

        vm.prank(devAlice);
        _perm(d).setWorkflowFactory(other);

        assertEq(_perm(d).getWorkflowFactory(), other);
    }

    function testJoinWorkflowNotFactory() public {
        (address d, ) = _createAgent();

        vm.prank(devAlice);
        _perm(d).setWorkflowFactory(address(123));

        vm.expectRevert(AgentPermissionFacet.NotWorkflowFactory.selector);
        vm.prank(other);
        _perm(d).joinWorkflow(user1);
    }

    function testJoinWorkflowZeroReverts() public {
        (address d, ) = _createAgent();

        vm.prank(devAlice);
        _perm(d).setWorkflowFactory(other);

        vm.expectRevert(AgentPermissionFacet.ZeroAddress.selector);
        vm.prank(other);
        _perm(d).joinWorkflow(ZERO);
    }

    function testJoinWorkflowNotReady() public {
        vm.prank(devAlice);
        (address d, ) = factory.createAgent(
            AgentFactory.CreateAgentParams({
                name: "A",
                description: "B",
                manifestHash: keccak256("m"),
                inputTypes: _arr(keccak256("type")),
                outputType: keccak256("out"),
                costPerRequest: 100,
                payoutAddress: devAlice,
                workflowReady: false
            })
        );

        vm.prank(devAlice);
        _perm(d).setWorkflowFactory(other);

        vm.expectRevert(AgentPermissionFacet.NotWorkflowReady.selector);
        vm.prank(other);
        _perm(d).joinWorkflow(user1);
    }

    function testJoinWorkflowHappyPath() public {
        (address d, ) = _createAgent();

        vm.prank(devAlice);
        _perm(d).setWorkflowFactory(other);

        vm.prank(other);
        _perm(d).joinWorkflow(user1);

        assertTrue(_perm(d).isTrustedCaller(user1));

        // idempotent
        vm.prank(other);
        _perm(d).joinWorkflow(user1);

        address[] memory list = _perm(d).getTrustedCallers();
        uint256 count;

        for (uint256 i; i < list.length; i++) {
            if (list[i] == user1) count++;
        }

        assertEq(count, 1);
    }
}
