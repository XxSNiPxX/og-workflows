// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface IAgentPermission {
    function setWorkflowFactory(address) external;

    function getWorkflowFactory() external view returns (address);
}

contract SetWorkflowFactory is Script {
    string memory root = vm.projectRoot();

    string memory WALLET_PATH =
        string.concat(root, "/script/deployments/wallets.json");

    string memory DEPLOY_PATH =
        string.concat(root, "/deployments/galileo.json");

    string memory NEW_PATH =
        string.concat(root, "/deployments/agents_new.json");

    uint256 privateKey;
    address signer;
    address workflowFactory;

    function run() external {
        loadConfig();

        console2.log("Signer:", signer);
        console2.log("WorkflowFactory:", workflowFactory);

        vm.startBroadcast(privateKey);

        configureNewAgents();

        vm.stopBroadcast();

        console2.log("done");
    }

    // ---------------- CONFIG ----------------

    function loadConfig() internal {
        string memory walletsRaw = vm.readFile(WALLET_PATH);
        string memory deployedRaw = vm.readFile(DEPLOY_PATH);

        privateKey = vm.parseUint(
            vm.parseJsonString(walletsRaw, ".agents[0].privateKey")
        );

        signer = vm.addr(privateKey);

        workflowFactory = vm.parseJsonAddress(deployedRaw, ".workflowFactory");
    }

    // ---------------- CORE ----------------

    function configureNewAgents() internal {
        string memory raw = vm.readFile(NEW_PATH);

        console2.log("reading agents_new.json");

        for (uint256 i = 0; i < 50; i++) {
            // 🔴 MATCH YOUR REAL KEYS
            string memory idKey = string.concat(vm.toString(i), "_id");
            string memory addrKey = string.concat(vm.toString(i), "_diamond");

            string memory idPath = string.concat('.agents["', idKey, '"]');
            string memory addrPath = string.concat('.agents["', addrKey, '"]');

            uint256 id;
            address agent;

            bool exists;

            // existence check
            try vm.parseJsonUint(raw, idPath) returns (uint256 parsedId) {
                id = parsedId;
                exists = true;
            } catch {
                exists = false;
            }

            if (!exists) {
                console2.log("stop at index", i);
                break;
            }

            agent = vm.parseJsonAddress(raw, addrPath);

            console2.log("agent:", agent);
            console2.log("id:", id);

            configureAgent(agent);
        }
    }

    // ---------------- ACTION ----------------

    function configureAgent(address agentAddr) internal {
        if (agentAddr == address(0)) return;

        IAgentPermission agent = IAgentPermission(agentAddr);

        address current = agent.getWorkflowFactory();

        if (current == workflowFactory) {
            console2.log("already set");
            return;
        }

        console2.log("setting workflowFactory...");

        agent.setWorkflowFactory(workflowFactory);

        console2.log("set complete");
    }
}
