// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface IAgentFactory {
    struct CreateParams {
        string name;
        string description;
        bytes32 manifestHash;
        bytes32[] inputTypes;
        bytes32 outputType;
        uint256 costPerRequest;
        address payoutAddress;
        bool workflowReady;
    }

    function createAgent(
        CreateParams calldata p
    ) external returns (address diamond, uint256 id);
}

interface IAgentPermission {
    function setWorkflowFactory(address) external;

    function getWorkflowFactory() external view returns (address);
}

contract CreateAgentsInline is Script {
    string constant DEPLOY_PATH = "deployments/galileo.json";
    string constant WALLET_PATH = "script/deployments/wallets.json";
    uint256 privateKey;
    address signer;

    address agentFactory;
    address workflowFactory;

    function run() external {
        loadConfig();

        vm.startBroadcast(privateKey);

        address[] memory agents = new address[](2);
        uint256[] memory ids = new uint256[](2);

        // 🔴 Agent 1: Wallet Analyzer
        (agents[0], ids[0]) = createAgent(
            "wallet_address",
            "wallet_analysis",
            "Analyzes a wallet address and extracts balances + activity",
            0.02 ether
        );

        // 🔴 Agent 2: PDF Generator
        (agents[1], ids[1]) = createAgent(
            "wallet_analysis",
            "pdf_report",
            "Formats wallet analysis into a human-readable PDF report",
            0.02 ether
        );

        vm.stopBroadcast();

        for (uint256 i = 0; i < agents.length; i++) {
            require(agents[i].code.length > 0, "DEPLOY FAILED");
        }

        for (uint256 i = 0; i < agents.length; i++) {
            setWorkflowFactorySafe(agents[i]);
        }

        saveNewAgents(agents, ids);

        console2.log("DONE");
    }

    function loadConfig() internal {
        string memory walletsRaw = vm.readFile(WALLET_PATH);
        string memory deployedRaw = vm.readFile(DEPLOY_PATH);

        privateKey = vm.parseUint(
            vm.parseJsonString(walletsRaw, ".agents[0].privateKey")
        );

        signer = vm.addr(privateKey);

        agentFactory = vm.parseJsonAddress(deployedRaw, ".agentFactory");
        workflowFactory = vm.parseJsonAddress(deployedRaw, ".workflowFactory");
    }

    function createAgent(
        string memory input,
        string memory output,
        string memory description,
        uint256 cost
    ) internal returns (address diamond, uint256 id) {
        IAgentFactory.CreateParams memory p;

        p.name = output;
        p.description = description;
        p.manifestHash = bytes32(0);

        p.inputTypes = new bytes32[](1);
        p.inputTypes[0] = keccak256(bytes(input));

        p.outputType = keccak256(bytes(output));

        p.costPerRequest = cost;
        p.payoutAddress = signer;
        p.workflowReady = true;

        (bool success, bytes memory data) = address(agentFactory).call(
            abi.encodeWithSelector(IAgentFactory.createAgent.selector, p)
        );

        require(success, "CREATE FAILED");

        (diamond, id) = abi.decode(data, (address, uint256));

        console2.log("agent:", diamond);
        console2.log("id:", id);

        require(diamond.code.length > 0, "INVALID DEPLOY");
    }

    function setWorkflowFactorySafe(address agent) internal {
        address current = IAgentPermission(agent).getWorkflowFactory();
        if (current == workflowFactory) return;

        vm.startBroadcast(privateKey);
        IAgentPermission(agent).setWorkflowFactory(workflowFactory);
        vm.stopBroadcast();
    }

    function saveNewAgents(
        address[] memory newAgents,
        uint256[] memory ids
    ) internal {
        string
            memory path = "/home/snip/Projects/web3/hello_foundry/deployments/agents_new.json";

        string memory obj;
        uint256 index = 0;

        for (uint256 i = 0; i < newAgents.length; i++) {
            if (newAgents[i] == address(0)) continue;

            string memory key = vm.toString(index);

            obj = vm.serializeUint("agents", string.concat(key, "_id"), ids[i]);
            obj = vm.serializeAddress(
                "agents",
                string.concat(key, "_diamond"),
                newAgents[i]
            );

            index++;
        }

        vm.writeJson(obj, path, ".agents");
    }
}
