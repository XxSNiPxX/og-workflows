// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// core
import "../src/AgentFactory.sol";
import "../src/AgentRegistry.sol";
import "../src/UserStateINFT.sol";
import "../src/UserStateLedger.sol";
import "../src/oracles/MockERC7857Oracle.sol";

// facets
import "../src/facets/DiamondCutFacet.sol";
import "../src/facets/DiamondLoupeFacet.sol";
import "../src/facets/OwnershipFacet.sol";
import "../src/facets/AgentManifestFacet.sol";
import "../src/facets/AgentPermissionFacet.sol";
import "../src/facets/AgentExecutionFacet.sol";
import "../src/facets/AgentAdminFacet.sol";

contract SmokeTest is Test {
    // roles
    address protocolAdmin = address(1);
    address inftAdmin = address(2);
    address oracleAdmin = address(3);
    address registryAdmin = address(4);
    address devAlice = address(7);
    address user1 = address(9);
    address worker1 = address(11);

    // contracts
    MockERC7857Oracle oracle;
    UserStateINFT inft;
    UserStateLedger ledger;
    AgentRegistry registry;
    AgentFactory factory;

    // facets
    DiamondCutFacet cutFacet;
    DiamondLoupeFacet loupeFacet;
    OwnershipFacet ownershipFacet;
    AgentManifestFacet manifestFacet;
    AgentPermissionFacet permissionFacet;
    AgentExecutionFacet executionFacet;
    AgentAdminFacet adminFacet;

    function setUp() public {
        vm.startPrank(oracleAdmin);
        oracle = new MockERC7857Oracle(oracleAdmin);
        vm.stopPrank();

        vm.startPrank(inftAdmin);
        inft = new UserStateINFT(inftAdmin, address(oracle));
        ledger = new UserStateLedger(address(inft));
        vm.stopPrank();

        vm.startPrank(registryAdmin);
        registry = new AgentRegistry(registryAdmin);
        vm.stopPrank();

        // deploy facets
        cutFacet = new DiamondCutFacet();
        loupeFacet = new DiamondLoupeFacet();
        ownershipFacet = new OwnershipFacet();
        manifestFacet = new AgentManifestFacet();
        permissionFacet = new AgentPermissionFacet();
        executionFacet = new AgentExecutionFacet();
        adminFacet = new AgentAdminFacet();

        // deploy factory
        vm.startPrank(protocolAdmin);
        factory = new AgentFactory(
            address(registry),
            address(inft),
            address(ledger),
            AgentFactory.FacetSet({
                diamondCutFacet: address(cutFacet),
                diamondLoupeFacet: address(loupeFacet),
                ownershipFacet: address(ownershipFacet),
                agentManifestFacet: address(manifestFacet),
                agentPermissionFacet: address(permissionFacet),
                agentExecutionFacet: address(executionFacet),
                agentAdminFacet: address(adminFacet)
            })
        );
        vm.stopPrank();

        vm.prank(registryAdmin);
        registry.setFactory(address(factory));
    }

    // ─────────────────────────────────────────────
    // Test 1 — deploy
    // ─────────────────────────────────────────────

    function testDeployProtocol() public {
        assertEq(inft.admin(), inftAdmin);
        assertEq(registry.factory(), address(factory));
        assertEq(factory.userStateINFT(), address(inft));
        assertEq(factory.userStateLedger(), address(ledger));
    }

    // ─────────────────────────────────────────────
    // Test 2 — mint + create agent
    // ─────────────────────────────────────────────

    function testMintAndCreateAgent() public {
        vm.prank(user1);
        inft.mint(user1, keccak256("data"), hex"1234", "ipfs://1");

        uint256 tokenId = inft.tokenIdOf(user1);
        assertEq(tokenId, 1);
        assertEq(inft.ownerOf(tokenId), user1);

        vm.prank(devAlice);
        (address diamond, uint256 id) = factory.createAgent(
            AgentFactory.CreateAgentParams({
                name: "agent",
                description: "test",
                manifestHash: keccak256("manifest"),
                inputTypes: _arr(keccak256("type:txt")),
                outputType: keccak256("type:result"),
                costPerRequest: 0.01 ether,
                payoutAddress: devAlice,
                workflowReady: true
            })
        );

        assertEq(id, 1);

        (address cfgInft, address cfgLedger) = AgentExecutionFacet(diamond)
            .getExecutionConfig();

        assertEq(cfgInft, address(inft));
        assertEq(cfgLedger, address(ledger));
    }

    // ─────────────────────────────────────────────
    // Test 3 — full flow
    // ─────────────────────────────────────────────

    function testFullFlow() public {
        vm.prank(user1);
        inft.mint(user1, keccak256("data"), hex"1234", "ipfs://1");
        uint256 tokenId = inft.tokenIdOf(user1);

        vm.prank(devAlice);
        (address diamond, ) = factory.createAgent(
            AgentFactory.CreateAgentParams({
                name: "agent",
                description: "test",
                manifestHash: keccak256("manifest"),
                inputTypes: _arr(keccak256("type:txt")),
                outputType: keccak256("type:result"),
                costPerRequest: 0.01 ether,
                payoutAddress: devAlice,
                workflowReady: true
            })
        );

        AgentPermissionFacet perm = AgentPermissionFacet(diamond);
        AgentExecutionFacet exec = AgentExecutionFacet(diamond);

        vm.prank(devAlice);
        perm.setWorker(worker1, true);
        assertTrue(perm.isWorker(worker1));

        vm.prank(user1);
        inft.authorizeUsage(tokenId, diamond, _encodeScope());

        assertTrue(
            inft.isAuthorizedFor(tokenId, diamond, keccak256("type:result"), 0)
        );

        // FIX 1: destructure return values
        vm.prank(user1);
        (bytes32 key, ) = exec.userRequest(
            tokenId,
            keccak256("input"),
            keccak256("type:txt")
        );

        vm.prank(worker1);
        exec.acknowledge(key);

        // FIX 2: enum instead of raw 0
        vm.prank(worker1);
        exec.complete(
            key,
            keccak256("ptr"),
            keccak256("type:result"),
            keccak256("hash"),
            keccak256("label"),
            IUserStateLedger.Visibility(0)
        );

        assertEq(ledger.totalItems(tokenId), 1);
    }

    // helpers

    function _arr(bytes32 a) internal pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = a;
    }

    function _encodeScope() internal pure returns (bytes memory) {
        bytes memory inner = abi.encode(
            true,
            true,
            true,
            _arr(keccak256("type:result")),
            _arrUint(0),
            uint64(0)
        );

        // prepend 0x20 offset manually (match abi.encode(struct))
        return bytes.concat(bytes32(uint256(32)), inner);
    }

    function _arrUint(uint256 a) internal pure returns (uint256[] memory r) {
        r = new uint256[](1);
        r[0] = a;
    }
}
