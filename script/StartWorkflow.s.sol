// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

interface IWorkflowInstance {
    function totalCost() external view returns (uint256);

    function start(uint256 tokenId, bytes32 inputPointer) external payable;
}

interface IINFT {
    function mint(
        address,
        bytes32,
        bytes calldata,
        string calldata
    ) external returns (uint256);

    function authorizeUsage(uint256, address, bytes calldata) external;

    function isAuthorized(uint256, address) external view returns (bool);

    function tokenIdOf(address) external view returns (uint256);
}

struct Permission {
    bool canExecute;
    bool canRead;
    bool canWrite;
    bytes32[] data;
    uint256[] nums;
    uint64 expiry;
}

contract StartWorkflow is Script {
    string memory root = vm.projectRoot();

    string memory WALLET_PATH =
        string.concat(root, "/script/deployments/wallets.json");

    string memory DEPLOY_PATH =
        string.concat(root, "/deployments/galileo.json");

    string memory NEW_PATH =
        string.concat(root, "/deployments/agents_new.json");

    uint256 privateKey;
    address signer;

    address workflow;
    address inft;
    address[] agents;

    function run() external {
        loadConfig();
        loadAgents();

        console2.log("User:", signer);
        console2.log("Workflow:", workflow);

        require(workflow.code.length > 0, "INVALID_WORKFLOW");

        uint256 cost = 0.03 ether; // or known constant
        console2.log("Cost:", cost);

        vm.startBroadcast(privateKey);

        uint256 tokenId = ensureMint();

        authorizeAgents(tokenId);
        authorizeWorkflow(tokenId);

        // 🔴 FIXED: correct signature
        IWorkflowInstance(workflow).start{value: cost}(tokenId, bytes32(0));

        vm.stopBroadcast();

        console2.log("DONE");
    }

    function loadConfig() internal {
        string memory walletsRaw = vm.readFile(WALLET_PATH);
        string memory deployedRaw = vm.readFile(DEPLOY_PATH);
        string memory workflowRaw = vm.readFile(WORKFLOW_PATH);

        privateKey = vm.parseUint(
            vm.parseJsonString(walletsRaw, ".users[0].privateKey")
        );

        signer = vm.addr(privateKey);

        workflow = vm.parseJsonAddress(workflowRaw, ".address");
        inft = vm.parseJsonAddress(deployedRaw, ".inft");

        require(workflow != address(0), "BAD_WORKFLOW");
        require(inft != address(0), "BAD_INFT");
    }

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

    function ensureMint() internal returns (uint256 tokenId) {
        tokenId = IINFT(inft).tokenIdOf(signer);

        if (tokenId != 0) return tokenId;

        tokenId = IINFT(inft).mint(
            signer,
            bytes32(0),
            bytes("key"),
            "ipfs://dummy"
        );

        require(tokenId != 0, "MINT_FAILED");
    }

    function authorizeAgents(uint256 tokenId) internal {
        Permission memory p = Permission({
            canExecute: true,
            canRead: true,
            canWrite: true,
            data: new bytes32[](0),
            nums: new uint256[](0),
            expiry: uint64(block.timestamp + 365 days)
        });

        bytes memory permission = abi.encode(p);

        for (uint256 i = 0; i < agents.length; i++) {
            if (!IINFT(inft).isAuthorized(tokenId, agents[i])) {
                IINFT(inft).authorizeUsage(tokenId, agents[i], permission);
            }
        }
    }

    function authorizeWorkflow(uint256 tokenId) internal {
        if (IINFT(inft).isAuthorized(tokenId, workflow)) return;

        Permission memory p = Permission({
            canExecute: true,
            canRead: true,
            canWrite: true,
            data: new bytes32[](0),
            nums: new uint256[](0),
            expiry: uint64(block.timestamp + 365 days)
        });

        IINFT(inft).authorizeUsage(tokenId, workflow, abi.encode(p));
    }
}
