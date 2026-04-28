// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/WorkflowFactory.sol";
import "../src/WorkflowRegistry.sol";
import "../src/ProtocolTreasury.sol";

import "./mocks/MockAgent.sol"; // REQUIRED

contract WorkflowFactoryTest is Test {
    WorkflowFactory factory;
    WorkflowRegistry registry;
    ProtocolTreasury treasury;

    address admin = address(1);
    address user = address(2);

    // ---------------------------------------------------------
    // SETUP
    // ---------------------------------------------------------

    function setUp() public {
        registry = new WorkflowRegistry(admin);
        treasury = new ProtocolTreasury(admin, address(0), 0);

        factory = new WorkflowFactory(
            address(registry),
            address(treasury),
            address(999), // dummy INFT (unused in unit tests)
            admin
        );

        vm.prank(admin);
        registry.setFactory(address(factory));

        vm.prank(admin);
        treasury.setFactory(address(factory));
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
    }

    // ---------------------------------------------------------
    // CONSTRUCTOR
    // ---------------------------------------------------------

    function testConstructorRejectsZero() public {
        vm.expectRevert(WorkflowFactory.ZeroAddress.selector);
        new WorkflowFactory(address(0), address(treasury), address(1), admin);

        vm.expectRevert(WorkflowFactory.ZeroAddress.selector);
        new WorkflowFactory(address(registry), address(0), address(1), admin);

        vm.expectRevert(WorkflowFactory.ZeroAddress.selector);
        new WorkflowFactory(
            address(registry),
            address(treasury),
            address(0),
            admin
        );

        vm.expectRevert(WorkflowFactory.ZeroAddress.selector);
        new WorkflowFactory(
            address(registry),
            address(treasury),
            address(1),
            address(0)
        );
    }

    // ---------------------------------------------------------
    // CREATE WORKFLOW
    // ---------------------------------------------------------

    function testCreateWorkflowEmptyReverts() public {
        WorkflowFactory.StepInput[]
            memory steps = new WorkflowFactory.StepInput[](0);

        vm.expectRevert(WorkflowFactory.EmptyWorkflow.selector);

        factory.createWorkflow(
            WorkflowFactory.CreateWorkflowParams({
                steps: steps,
                name: "x",
                description: "y",
                admin: address(0)
            })
        );
    }

    function testCreateWorkflowHappy() public {
        (MockAgent a1, MockAgent a2) = _twoAgents();

        WorkflowFactory.StepInput[]
            memory steps = new WorkflowFactory.StepInput[](2);

        steps[0] = WorkflowFactory.StepInput({
            agent: address(a1),
            inputType: keccak256("txt"),
            outputType: keccak256("emb")
        });

        steps[1] = WorkflowFactory.StepInput({
            agent: address(a2),
            inputType: keccak256("emb"),
            outputType: keccak256("vec")
        });

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

        // treasury wiring
        assertTrue(treasury.isRegistered(wf));

        // registry wiring
        assertEq(registry.getWorkflow(id).workflowAddress, wf);

        // permission wiring
        assertTrue(a1.isTrustedCaller(wf));
        assertTrue(a2.isTrustedCaller(wf));
    }

    // ---------------------------------------------------------
    // QUOTE
    // ---------------------------------------------------------

    function testQuoteWorkflow() public {
        (MockAgent a1, MockAgent a2) = _twoAgents();

        WorkflowFactory.StepInput[]
            memory steps = new WorkflowFactory.StepInput[](2);

        steps[0] = WorkflowFactory.StepInput({
            agent: address(a1),
            inputType: keccak256("txt"),
            outputType: keccak256("emb")
        });

        steps[1] = WorkflowFactory.StepInput({
            agent: address(a2),
            inputType: keccak256("emb"),
            outputType: keccak256("vec")
        });

        (uint256[] memory perStep, uint256 total) = factory.quoteWorkflow(
            steps
        );

        assertEq(perStep[0], 0.01 ether);
        assertEq(perStep[1], 0.02 ether);
        assertEq(total, 0.03 ether);
    }
}
