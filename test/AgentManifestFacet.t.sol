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

contract AgentManifestFacetTest is Test {
    // roles
    address protocolAdmin = address(1);
    address registryAdmin = address(2);
    address oracleAdmin = address(3);

    address devAlice = address(10);
    address devBob = address(11);
    address payoutAlice = address(12);
    address payoutBob = address(13);
    address other = address(99);

    // core
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

    function H(string memory s) internal pure returns (bytes32) {
        return keccak256(bytes(s));
    }

    function setUp() public {
        vm.prank(oracleAdmin);
        oracle = new MockERC7857Oracle(oracleAdmin);

        vm.prank(protocolAdmin);
        inft = new UserStateINFT(protocolAdmin, address(oracle));
        ledger = new UserStateLedger(address(inft));

        vm.prank(registryAdmin);
        registry = new AgentRegistry(registryAdmin);

        // deploy facets
        cutFacet = new DiamondCutFacet();
        loupeFacet = new DiamondLoupeFacet();
        ownershipFacet = new OwnershipFacet();
        manifestFacet = new AgentManifestFacet();
        permissionFacet = new AgentPermissionFacet();
        executionFacet = new AgentExecutionFacet();
        adminFacet = new AgentAdminFacet();

        vm.prank(protocolAdmin);
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

        vm.prank(registryAdmin);
        registry.setFactory(address(factory));
    }

    // =============================================================
    // HELPERS
    // =============================================================

    struct Agent {
        address diamond;
        uint256 id;
        AgentManifestFacet manifest;
        AgentAdminFacet admin;
        OwnershipFacet ownership;
        DiamondLoupeFacet loupe;
    }

    function createAgent(
        address dev,
        string memory name,
        string memory description,
        bytes32 manifestHash,
        bytes32[] memory inputs,
        bytes32 output,
        uint256 price,
        address payout,
        bool workflowReady
    ) internal returns (Agent memory a) {
        vm.prank(dev);
        (a.diamond, a.id) = factory.createAgent(
            AgentFactory.CreateAgentParams({
                name: name,
                description: description,
                manifestHash: manifestHash,
                inputTypes: inputs,
                outputType: output,
                costPerRequest: price,
                payoutAddress: payout,
                workflowReady: workflowReady
            })
        );

        a.manifest = AgentManifestFacet(a.diamond);
        a.admin = AgentAdminFacet(a.diamond);
        a.ownership = OwnershipFacet(a.diamond);
        a.loupe = DiamondLoupeFacet(a.diamond);
    }

    // =============================================================
    // MANIFEST READ
    // =============================================================

    function testGetManifest() public {
        bytes32[] memory ins = new bytes32[](2);
        ins[0] = H("type:txt");
        ins[1] = H("type:html");

        Agent memory a = createAgent(
            devAlice,
            "Vector",
            "embeddings",
            H("v1"),
            ins,
            H("type:vec"),
            1234,
            payoutAlice,
            true
        );

        LibAgentManifestStorage.AgentManifest memory m = a
            .manifest
            .getManifest();

        assertEq(m.name, "Vector");
        assertEq(m.description, "embeddings");
        assertEq(m.outputType, H("type:vec"));
        assertEq(m.costPerRequest, 1234);
        assertEq(m.payoutAddress, payoutAlice);
        assertTrue(m.workflowReady);
        assertFalse(m.paused);
    }

    function testSupportsInput() public {
        bytes32[] memory ins = new bytes32[](1);
        ins[0] = H("type:txt");

        Agent memory a = createAgent(
            devAlice,
            "A",
            "B",
            H("h"),
            ins,
            H("out"),
            1,
            payoutAlice,
            true
        );

        assertTrue(a.manifest.supportsInput(H("type:txt")));
        assertFalse(a.manifest.supportsInput(H("other")));
    }

    // =============================================================
    // ADMIN MUTATIONS
    // =============================================================

    function testAdminUpdates() public {
        Agent memory a = createAgent(
            devAlice,
            "A",
            "B",
            H("h"),
            _arr(H("x")),
            H("out"),
            100,
            payoutAlice,
            true
        );

        vm.prank(devAlice);
        a.manifest.setPrice(500);

        vm.prank(devAlice);
        a.manifest.setPayoutAddress(payoutBob);

        vm.prank(devAlice);
        a.manifest.setPaused(true);

        vm.prank(devAlice);
        a.manifest.setWorkflowReady(false);

        LibAgentManifestStorage.AgentManifest memory m = a
            .manifest
            .getManifest();

        assertEq(m.costPerRequest, 500);
        assertEq(m.payoutAddress, payoutBob);
        assertTrue(m.paused);
        assertFalse(m.workflowReady);
    }

    // =============================================================
    // ADMIN FACET
    // =============================================================

    function testAdminTransfer() public {
        Agent memory a = createAgent(
            devAlice,
            "A",
            "B",
            H("h"),
            _arr(H("x")),
            H("out"),
            100,
            payoutAlice,
            true
        );

        assertEq(a.admin.admin(), devAlice);

        vm.prank(devAlice);
        a.admin.setAdmin(devBob);

        assertEq(a.admin.admin(), devBob);
    }

    function testSyncToRegistry() public {
        Agent memory a = createAgent(
            devAlice,
            "A",
            "B",
            H("h"),
            _arr(H("x")),
            H("out"),
            100,
            payoutAlice,
            true
        );

        vm.prank(devAlice);
        a.manifest.setPrice(777);

        vm.prank(devAlice);
        a.admin.syncToRegistry(address(registry), a.id);

        IAgentRegistry.AgentRecord memory rec = registry.getAgent(a.id);
        assertEq(rec.costPerRequest, 777);
    }

    // =============================================================
    // LOUPE
    // =============================================================

    function testLoupe() public {
        Agent memory a = createAgent(
            devAlice,
            "A",
            "B",
            H("h"),
            _arr(H("x")),
            H("out"),
            100,
            payoutAlice,
            true
        );

        address[] memory addrs = a.loupe.facetAddresses();
        assertEq(addrs.length, 7);
    }

    // =============================================================
    // HELPERS
    // =============================================================

    function _arr(bytes32 a) internal pure returns (bytes32[] memory r) {
        r = new bytes32[](1);
        r[0] = a;
    }
}
