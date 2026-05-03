// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

// core
import "../src/ProtocolTreasury.sol";
import "../src/UserStateINFT.sol";
import "../src/UserStateLedger.sol";
import "../src/WorkflowFactory.sol";
import "../src/WorkflowRegistry.sol";
import "../src/AgentRegistry.sol";
import "../src/AgentFactory.sol";
import "../src/oracles/MockERC7857Oracle.sol";

// facets
import "../src/facets/DiamondCutFacet.sol";
import "../src/facets/DiamondLoupeFacet.sol";
import "../src/facets/OwnershipFacet.sol";
import "../src/facets/AgentManifestFacet.sol";
import "../src/facets/AgentPermissionFacet.sol";
import "../src/facets/AgentExecutionFacet.sol";
import "../src/facets/AgentAdminFacet.sol";

contract DeployFull is Script {
    uint256 constant PRIVATE_KEY =
        s;

    function run() external {
        address deployer = vm.addr(PRIVATE_KEY);
        console2.log("Deployer:", deployer);

        vm.startBroadcast(PRIVATE_KEY);

        // ==================================================
        // CORE
        // ==================================================

        MockERC7857Oracle oracle = new MockERC7857Oracle(deployer);

        UserStateINFT inft = new UserStateINFT(deployer, address(oracle));
        UserStateLedger ledger = new UserStateLedger(address(inft));

        WorkflowRegistry workflowRegistry = new WorkflowRegistry(deployer);
        ProtocolTreasury treasury = new ProtocolTreasury(deployer, deployer, 0);
        AgentRegistry agentRegistry = new AgentRegistry(deployer);

        console2.log("Core deployed");

        // ==================================================
        // FACETS
        // ==================================================

        DiamondCutFacet cutFacet = new DiamondCutFacet();
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();

        AgentManifestFacet manifestFacet = new AgentManifestFacet();
        AgentPermissionFacet permissionFacet = new AgentPermissionFacet();
        AgentExecutionFacet executionFacet = new AgentExecutionFacet();
        AgentAdminFacet adminFacet = new AgentAdminFacet();

        console2.log("Facets deployed");

        // ==================================================
        // WORKFLOW FACTORY
        // ==================================================

        WorkflowFactory workflowFactory = new WorkflowFactory(
            address(treasury) // 🔴 ONLY ARG NOW
        );

        console2.log("WorkflowFactory:", address(workflowFactory));

        require(address(workflowFactory).code.length > 0, "WF NOT DEPLOYED");

        // sanity check
        (bool ok, ) = address(workflowFactory).staticcall(
            abi.encodeWithSelector(
                WorkflowFactory.createWorkflow.selector,
                new WorkflowFactory.Step[](0),
                "",
                "",
                address(0)
            )
        );

        require(!ok, "WF SELECTOR BROKEN");
        console2.log("WorkflowFactory verified");
        // ==================================================
        // AGENT FACTORY (FIXED)
        // ==================================================

        AgentFactory.FacetSet memory facets = AgentFactory.FacetSet({
            diamondCutFacet: address(cutFacet),
            diamondLoupeFacet: address(loupeFacet),
            ownershipFacet: address(ownershipFacet),
            agentManifestFacet: address(manifestFacet),
            agentPermissionFacet: address(permissionFacet),
            agentExecutionFacet: address(executionFacet),
            agentAdminFacet: address(adminFacet)
        });

        // 🔴 FIX: pass workflowFactory into AgentFactory
        AgentFactory agentFactory = new AgentFactory(
            address(agentRegistry),
            address(inft),
            address(ledger),
            address(workflowFactory), // 🔴 NEW
            facets
        );

        console2.log("AgentFactory:", address(agentFactory));

        require(address(agentFactory).code.length > 0, "AF NOT DEPLOYED");

        // ==================================================
        // WIRING
        // ==================================================

        workflowRegistry.setFactory(address(workflowFactory));
        treasury.setFactory(address(workflowFactory));
        agentRegistry.setFactory(address(agentFactory));

        require(
            workflowRegistry.factory() == address(workflowFactory),
            "WF REGISTRY FAIL"
        );

        require(
            agentRegistry.factory() == address(agentFactory),
            "AGENT REGISTRY FAIL"
        );

        require(
            treasury.factory() == address(workflowFactory),
            "TREASURY FAIL"
        );

        console2.log("Wiring verified");

        vm.stopBroadcast();

        // ==================================================
        // SAVE
        // ==================================================

        string memory path = "./deployments/galileo.json";
        string memory obj;

        obj = vm.serializeAddress("contracts", "oracle", address(oracle));
        obj = vm.serializeAddress("contracts", "inft", address(inft));
        obj = vm.serializeAddress("contracts", "ledger", address(ledger));

        obj = vm.serializeAddress(
            "contracts",
            "workflowRegistry",
            address(workflowRegistry)
        );
        obj = vm.serializeAddress(
            "contracts",
            "workflowFactory",
            address(workflowFactory)
        );
        obj = vm.serializeAddress(
            "contracts",
            "agentRegistry",
            address(agentRegistry)
        );
        obj = vm.serializeAddress(
            "contracts",
            "agentFactory",
            address(agentFactory)
        );

        vm.writeJson(obj, path);

        console2.log("Saved:", path);
        console2.log("DEPLOYMENT COMPLETE");
    }
}
