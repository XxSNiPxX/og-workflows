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

import "../src/libraries/LibAgentExecutionStorage.sol";
import "../src/libraries/LibPermissionScope.sol";
import "../src/interfaces/IUserStateLedger.sol";

contract AgentExecutionFacetTest is Test {
    AgentFactory factory;
    AgentRegistry registry;
    UserStateINFT inft;
    UserStateLedger ledger;
    MockERC7857Oracle oracle;

    address devAlice = address(10);
    address worker1 = address(20);
    address user1 = address(30);

    // ---------------------------------------------------------
    // SETUP
    // ---------------------------------------------------------

    function setUp() public {
        oracle = new MockERC7857Oracle(address(this));
        inft = new UserStateINFT(address(this), address(oracle));
        ledger = new UserStateLedger(address(inft));
        registry = new AgentRegistry(address(this));

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

        registry.setFactory(address(factory));
    }

    // ---------------------------------------------------------
    // HELPERS
    // ---------------------------------------------------------

    function _createAgent() internal returns (address d) {
        vm.prank(devAlice);
        (d, ) = factory.createAgent(
            AgentFactory.CreateAgentParams({
                name: "A",
                description: "B",
                manifestHash: keccak256("m"),
                inputTypes: _arr(keccak256("type:txt")),
                outputType: keccak256("type:result"),
                costPerRequest: 0,
                payoutAddress: devAlice,
                workflowReady: true
            })
        );
    }

    function _arr(bytes32 a) internal pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = a;
    }

    function _exec(address d) internal pure returns (AgentExecutionFacet) {
        return AgentExecutionFacet(d);
    }

    function _perm(address d) internal pure returns (AgentPermissionFacet) {
        return AgentPermissionFacet(d);
    }

    function _permBytes() internal pure returns (bytes memory) {
        LibPermissionScope.PermissionScope memory s;

        s.canRead = true;
        s.canWrite = true;
        s.canAppend = false;

        s.allowedTypes = new bytes32[](1);
        s.allowedTypes[0] = keccak256("type:result");

        s.allowedWorkflowIds = new uint256[](1);
        s.allowedWorkflowIds[0] = 0;

        s.expiresAt = 0;

        return LibPermissionScope.encode(s);
    }

    // ---------------------------------------------------------
    // BASIC FLOW
    // ---------------------------------------------------------

    function testUserRequestHappy() public {
        address d = _createAgent();

        uint256 tokenId = inft.mint(user1, keccak256("u"), hex"01", "uri");

        vm.prank(user1);
        inft.authorizeUsage(tokenId, d, _permBytes());

        vm.prank(devAlice);
        _perm(d).setWorker(worker1, true);

        vm.prank(user1);
        (bytes32 key, ) = _exec(d).userRequest(
            tokenId,
            keccak256("i"),
            keccak256("type:txt")
        );

        assertTrue(key != bytes32(0));
        assertEq(_exec(d).totalRequests(), 1);
    }

    function testAcknowledgeFlow() public {
        address d = _createAgent();

        uint256 tokenId = inft.mint(user1, keccak256("u"), hex"01", "uri");

        vm.prank(user1);
        inft.authorizeUsage(tokenId, d, _permBytes());

        vm.prank(devAlice);
        _perm(d).setWorker(worker1, true);

        vm.prank(user1);
        (bytes32 key, ) = _exec(d).userRequest(
            tokenId,
            keccak256("i"),
            keccak256("type:txt")
        );

        vm.prank(worker1);
        _exec(d).acknowledge(key);

        LibAgentExecutionStorage.RequestRecord memory r = _exec(d).getRequest(
            key
        );

        assertEq(uint256(r.status), 2); // PROCESSING
    }

    function testCompleteFlow() public {
        address d = _createAgent();

        uint256 tokenId = inft.mint(user1, keccak256("u"), hex"01", "uri");

        vm.prank(user1);
        inft.authorizeUsage(tokenId, d, _permBytes());

        vm.prank(devAlice);
        _perm(d).setWorker(worker1, true);

        vm.prank(user1);
        (bytes32 key, ) = _exec(d).userRequest(
            tokenId,
            keccak256("i"),
            keccak256("type:txt")
        );

        vm.prank(worker1);
        _exec(d).acknowledge(key);

        vm.prank(worker1);
        _exec(d).complete(
            key,
            keccak256("op"),
            keccak256("type:result"),
            bytes32(0),
            bytes32(0),
            IUserStateLedger.Visibility.PUBLIC // 🔴 critical fix
        );

        LibAgentExecutionStorage.RequestRecord memory r = _exec(d).getRequest(
            key
        );

        assertEq(uint256(r.status), 3); // COMPLETED
    }
}
