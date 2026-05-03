// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/WorkflowFactory.sol";
import "../src/WorkflowRegistry.sol";
import "../src/ProtocolTreasury.sol";
import "../src/AgentRegistry.sol";

import "./mocks/MockAgent.sol";

contract MockLedger {
    function appendItem(
        uint256,
        address,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }
}

contract WorkflowFactoryTest is Test {
    WorkflowFactory factory;
    WorkflowRegistry registry;
    ProtocolTreasury treasury;
    AgentRegistry agentRegistry;

    address admin = address(1);
    address user = address(2);

    address dummyINFT = address(999);
    MockLedger ledger;

    function setUp() public {
        registry = new WorkflowRegistry(admin);
        treasury = new ProtocolTreasury(admin, address(0), 0);
        agentRegistry = new AgentRegistry(admin);

        ledger = new MockLedger();

        factory = new WorkflowFactory(
            address(registry),
            address(treasury),
            address(agentRegistry), // ✅ NEW
            dummyINFT,
            address(ledger),
            admin
        );

        vm.prank(admin);
        registry.setFactory(address(factory));

        vm.prank(admin);
        treasury.setFactory(address(factory));
    }

    function _register(
        address agent,
        bytes32 input,
        bytes32 output,
        uint256 cost,
        address payout
    ) internal {
        bytes32[] memory inputs = new bytes32[](1);
        inputs[0] = input;

        vm.prank(admin);
        agentRegistry.setFactory(admin);

        vm.prank(admin);
        agentRegistry.registerAgent(
            IAgentRegistry.RegisterParams({
                agentAddress: agent,
                creator: admin,
                admin: admin,
                payoutAddress: payout,
                inputTypes: inputs,
                outputType: output,
                costPerRequest: cost,
                workflowReady: true,
                name: "agent",
                description: "",
                manifestHash: bytes32(0)
            })
        );
    }

    function _twoAgents() internal returns (MockAgent a1, MockAgent a2) {
        a1 = new MockAgent(
            keccak256("txt"),
            keccak256("emb"),
            0.01 ether,
            address(11)
        );
        a2 = new MockAgent(
            keccak256("emb"),
            keccak256("vec"),
            0.02 ether,
            address(12)
        );

        _register(
            address(a1),
            keccak256("txt"),
            keccak256("emb"),
            0.01 ether,
            address(11)
        );
        _register(
            address(a2),
            keccak256("emb"),
            keccak256("vec"),
            0.02 ether,
            address(12)
        );
    }

    function testCreateWorkflowHappy() public {
        (MockAgent a1, MockAgent a2) = _twoAgents();

        WorkflowFactory.StepInput[]
            memory steps = new WorkflowFactory.StepInput[](2);

        steps[0] = WorkflowFactory.StepInput(
            address(a1),
            keccak256("txt"),
            keccak256("emb")
        );
        steps[1] = WorkflowFactory.StepInput(
            address(a2),
            keccak256("emb"),
            keccak256("vec")
        );

        vm.prank(user);
        (address wf, uint256 id) = factory.createWorkflow(
            WorkflowFactory.CreateWorkflowParams({
                steps: steps,
                name: "wf",
                description: "test",
                admin: address(0)
            })
        );

        assertTrue(wf != address(0));
        assertEq(id, 1);

        assertTrue(treasury.isRegistered(wf));
        assertEq(registry.getWorkflow(id).workflowAddress, wf);

        assertTrue(a1.isTrustedCaller(wf));
        assertTrue(a2.isTrustedCaller(wf));
    }
}
