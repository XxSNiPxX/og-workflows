// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

// ---------------- INTERFACES ----------------

interface IWorkflowFactory {
    struct Step {
        address agent;
        bytes32 inputType;
        bytes32 outputType;
    }

    function createWorkflow(
        Step[] calldata steps,
        string calldata name,
        string calldata desc,
        address owner
    ) external returns (address workflow);
}

interface IAgentView {
    function getInputTypes() external view returns (bytes32[] memory);

    function getOutputType() external view returns (bytes32);

    function supportsInput(bytes32) external view returns (bool);

    function isPaused() external view returns (bool);
}

interface IAgentPermission {
    function getWorkflowFactory() external view returns (address);
}

interface IAgentManifest {
    function isWorkflowReady() external view returns (bool);
}

// ---------------- SCRIPT ----------------

contract CreateWorkflow is Script {
    string memory root = vm.projectRoot();

    string memory WALLET_PATH =
        string.concat(root, "/script/deployments/wallets.json");

    string memory DEPLOY_PATH =
        string.concat(root, "/deployments/galileo.json");

    string memory AGENTS_PATH =
        string.concat(root, "/deployments/agents_new.json");

    string memory SAVE_PATH =
        string.concat(root, "/deployments/workflows_new.json");
    uint256 privateKey;
    address signer;
    address workflowFactory;

    address[] agents;

    function run() external {
        loadConfig();
        loadAgents();

        console2.log("Signer:", signer);
        console2.log("WorkflowFactory:", workflowFactory);

        require(workflowFactory.code.length > 0, "FACTORY NOT DEPLOYED");

        validateAgents();

        IWorkflowFactory.Step[] memory steps = buildSteps();

        console2.log("Steps:", steps.length);

        vm.startBroadcast(privateKey);

        address workflow = IWorkflowFactory(workflowFactory).createWorkflow(
            steps,
            "pipeline",
            "auto",
            signer
        );

        vm.stopBroadcast();

        console2.log("Workflow:", workflow);

        require(workflow != address(0), "INVALID WORKFLOW");

        saveWorkflow(workflow);
    }

    // ---------------- CONFIG ----------------

    function loadConfig() internal {
        string memory walletsRaw = vm.readFile(WALLET_PATH);
        string memory deployedRaw = vm.readFile(DEPLOY_PATH);

        privateKey = vm.parseUint(
            vm.parseJsonString(walletsRaw, ".users[0].privateKey")
        );

        signer = vm.addr(privateKey);

        workflowFactory = vm.parseJsonAddress(deployedRaw, ".workflowFactory");
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
                if (a.code.length == 0) {
                    console2.log("SKIP non-contract:", a);
                    continue;
                }

                console2.log("Loaded agent:", a);
                temp[count++] = a;
            } catch {
                break;
            }
        }

        require(count > 0, "NO VALID AGENTS");

        agents = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            agents[i] = temp[i];
        }
    }

    // ---------------- VALIDATION ----------------

    function validateAgents() internal view {
        for (uint256 i = 0; i < agents.length; i++) {
            address a = agents[i];

            require(
                IAgentPermission(a).getWorkflowFactory() == workflowFactory,
                "FACTORY MISMATCH"
            );

            require(IAgentManifest(a).isWorkflowReady(), "NOT WORKFLOW READY");

            console2.log("validated:", a);
        }
    }

    // ---------------- BUILD STEPS ----------------

    function buildSteps()
        internal
        view
        returns (IWorkflowFactory.Step[] memory)
    {
        require(agents.length >= 2, "NEED AT LEAST 2 AGENTS");

        address a0 = agents[0];
        address a1 = agents[1];

        IAgentView agent0 = IAgentView(a0);
        IAgentView agent1 = IAgentView(a1);

        require(!agent0.isPaused(), "AGENT0 PAUSED");
        require(!agent1.isPaused(), "AGENT1 PAUSED");

        // ---------------- STEP 0 ----------------

        bytes32[] memory inputs0 = agent0.getInputTypes();
        require(inputs0.length > 0, "AGENT0 NO INPUTS");

        bytes32 input0 = inputs0[0]; // first step can take anything
        bytes32 output0 = agent0.getOutputType();

        require(agent0.supportsInput(input0), "AGENT0 BAD INPUT");

        // ---------------- STEP 1 ----------------

        bytes32[] memory inputs1 = agent1.getInputTypes();
        require(inputs1.length > 0, "AGENT1 NO INPUTS");

        bytes32 input1;
        bool found;

        for (uint256 i = 0; i < inputs1.length; i++) {
            if (inputs1[i] == output0) {
                input1 = inputs1[i];
                found = true;
                break;
            }
        }

        require(found, "PIPELINE BREAK: agent1 cannot consume agent0 output");

        bytes32 output1 = agent1.getOutputType();

        require(agent1.supportsInput(input1), "AGENT1 BAD INPUT");

        // ---------------- BUILD ----------------

        IWorkflowFactory.Step[] memory steps = new IWorkflowFactory.Step[](2);

        steps[0] = IWorkflowFactory.Step({
            agent: a0,
            inputType: input0,
            outputType: output0
        });

        steps[1] = IWorkflowFactory.Step({
            agent: a1,
            inputType: input1,
            outputType: output1
        });

        console2.log("Step0 agent:", a0);
        console2.log("Step1 agent:", a1);

        return steps;
    }

    // ---------------- SAVE ----------------

    function saveWorkflow(address workflow) internal {
        string memory obj;

        obj = vm.serializeAddress("workflow", "address", workflow);
        obj = vm.serializeAddress("workflow", "creator", signer);
        obj = vm.serializeUint("workflow", "block", block.number);

        vm.writeJson(obj, SAVE_PATH);

        console2.log("Saved workflows_new.json");
    }
}
