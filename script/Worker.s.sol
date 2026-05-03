// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

// ---------------- INTERFACE ----------------

interface IAgent {
    function complete(
        bytes32 key,
        bytes32 outputPointer,
        bytes32 outputType,
        bytes32 outputHash,
        bytes32 labelHash,
        uint8 visibility
    ) external returns (uint256);

    function getOutputType() external view returns (bytes32);
}

// ---------------- SCRIPT ----------------

contract Worker is Script {
    string constant WALLET_PATH =
        "/home/snip/Projects/web3/hello_foundry/script/deployments/wallets.json";

    string constant AGENTS_PATH =
        "/home/snip/Projects/web3/hello_foundry/deployments/agents_new.json";

    uint256 privateKey;
    address signer;

    address[] agents;

    function run() external {
        loadConfig();
        loadAgents();

        console2.log("Worker:", signer);

        vm.startBroadcast(privateKey);

        // 🔴 MANUAL execution (replace with real keys)
        for (uint256 i = 0; i < agents.length; i++) {
            console2.log("\n--- Agent ---", agents[i]);

            // Example dummy key (you MUST replace with real key)
            bytes32 key = bytes32(0);

            execute(agents[i], key);
        }

        vm.stopBroadcast();

        console2.log("DONE");
    }

    // ---------------- LOAD CONFIG ----------------

    function loadConfig() internal {
        string memory walletsRaw = vm.readFile(WALLET_PATH);

        privateKey = vm.parseUint(
            vm.parseJsonString(walletsRaw, ".agents[0].privateKey")
        );

        signer = vm.addr(privateKey);
    }

    // ---------------- LOAD AGENTS ----------------

    function loadAgents() internal {
        string memory raw = vm.readFile(AGENTS_PATH);

        address[] memory temp = new address[](20);
        uint256 count = 0;

        for (uint256 i = 0; i < 20; i++) {
            string memory key = string.concat(vm.toString(i), "_diamond");
            string memory path = string.concat('.agents["', key, '"]');

            try vm.parseJsonAddress(raw, path) returns (address a) {
                console2.log("Loaded agent:", a);
                temp[count++] = a;
            } catch {
                break;
            }
        }

        require(count > 0, "NO AGENTS");

        agents = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            agents[i] = temp[i];
        }
    }

    // ---------------- EXECUTE ----------------

    function execute(address agent, bytes32 key) internal {
        if (key == bytes32(0)) {
            console2.log("Skipping empty key");
            return;
        }

        IAgent a = IAgent(agent);

        bytes32 outputPointer = keccak256(
            abi.encodePacked(block.timestamp, key)
        );

        bytes32 outputHash = keccak256("result");

        bytes32 outputType = a.getOutputType();

        bytes32 labelHash = bytes32(0);
        uint8 visibility = 0;

        try
            a.complete(
                key,
                outputPointer,
                outputType,
                outputHash,
                labelHash,
                visibility
            )
        {
            console2.log("COMPLETED");
        } catch {
            console2.log("FAILED");
        }
    }
}
