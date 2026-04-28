// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/WorkflowRegistry.sol";
import "../src/interfaces/IWorkflowRegistry.sol";

contract WorkflowRegistryTest is Test {
    WorkflowRegistry registry;

    address admin = address(1);
    address other = address(2);

    address devAlice = address(10);
    address devBob = address(11);
    address user1 = address(20);

    // ---------------------------------------------------------
    // SETUP
    // ---------------------------------------------------------

    function setUp() public {
        registry = new WorkflowRegistry(admin);
    }

    // ---------------------------------------------------------
    // HELPERS
    // ---------------------------------------------------------

    function _params(
        address workflowAddr,
        address creator,
        string memory name
    ) internal pure returns (IWorkflowRegistry.RegisterParams memory p) {
        p = IWorkflowRegistry.RegisterParams({
            workflowAddress: workflowAddr,
            creator: creator,
            inputType: keccak256("a"),
            outputType: keccak256("z"),
            totalCost: 0,
            stepCount: 1,
            name: name,
            description: ""
        });
    }

    function _setupFactory() internal {
        vm.prank(admin);
        registry.setFactory(other);
    }

    function _seedThree() internal {
        _setupFactory();

        vm.startPrank(other);

        registry.registerWorkflow(_params(address(101), devAlice, "a1"));
        registry.registerWorkflow(_params(address(102), devBob, "b1"));
        registry.registerWorkflow(_params(address(103), devAlice, "a2"));

        vm.stopPrank();
    }

    // ---------------------------------------------------------
    // CONSTRUCTOR / CONFIG
    // ---------------------------------------------------------

    function testConstructorRejectsZeroAdmin() public {
        vm.expectRevert(WorkflowRegistry.ZeroAddress.selector);
        new WorkflowRegistry(address(0));
    }

    function testSetFactory() public {
        vm.expectRevert(WorkflowRegistry.NotAdmin.selector);
        registry.setFactory(other);

        vm.prank(admin);
        vm.expectRevert(WorkflowRegistry.ZeroAddress.selector);
        registry.setFactory(address(0));
    }

    function testSetAdmin() public {
        vm.expectRevert(WorkflowRegistry.NotAdmin.selector);
        registry.setAdmin(other);

        vm.prank(admin);
        registry.setAdmin(other);

        assertEq(registry.admin(), other);
    }

    function testSetPaused() public {
        vm.expectRevert(WorkflowRegistry.NotAdmin.selector);
        registry.setPaused(true);

        vm.prank(admin);
        registry.setPaused(true);

        assertTrue(registry.registryPaused());
    }

    // ---------------------------------------------------------
    // REGISTER WORKFLOW
    // ---------------------------------------------------------

    function testRegisterNonFactoryReverts() public {
        vm.expectRevert(WorkflowRegistry.NotFactory.selector);
        registry.registerWorkflow(_params(user1, user1, "x"));
    }

    function testRegisterZeroAddressReverts() public {
        _setupFactory();

        vm.prank(other);
        vm.expectRevert(WorkflowRegistry.ZeroAddress.selector);

        registry.registerWorkflow(_params(address(0), user1, "x"));
    }

    function testRegisterHappy() public {
        _setupFactory();

        vm.prank(other);
        registry.registerWorkflow(_params(user1, devAlice, "wf1"));

        IWorkflowRegistry.WorkflowRecord memory rec = registry.getWorkflow(1);

        assertEq(rec.workflowAddress, user1);
        assertEq(rec.creator, devAlice);
        assertEq(rec.totalCost, 0);
        assertTrue(rec.active);
    }

    function testRegisterDuplicateReverts() public {
        _setupFactory();

        IWorkflowRegistry.RegisterParams memory p = _params(
            user1,
            devAlice,
            "x"
        );

        vm.prank(other);
        registry.registerWorkflow(p);

        vm.prank(other);
        vm.expectRevert(WorkflowRegistry.AlreadyRegistered.selector);
        registry.registerWorkflow(p);
    }

    function testPausedRegistryReverts() public {
        _setupFactory();

        vm.prank(admin);
        registry.setPaused(true);

        vm.prank(other);
        vm.expectRevert(WorkflowRegistry.Paused.selector);

        registry.registerWorkflow(_params(user1, devAlice, "x"));
    }

    // ---------------------------------------------------------
    // LISTING
    // ---------------------------------------------------------

    function testListAllWorkflows() public {
        _seedThree();

        (IWorkflowRegistry.WorkflowRecord[] memory page, ) = registry
            .listAllWorkflows(0, 100);

        assertEq(page.length, 3);
    }

    function testListByCreator() public {
        _seedThree();

        (IWorkflowRegistry.WorkflowRecord[] memory page, ) = registry
            .listWorkflowsByCreator(devAlice, 0, 100);

        assertEq(page.length, 2);
    }

    function testTotalWorkflows() public {
        _seedThree();

        assertEq(registry.totalWorkflows(), 3);
    }

    function testListActiveWorkflows() public {
        _seedThree();

        vm.prank(admin);
        registry.setWorkflowActive(2, false);

        (IWorkflowRegistry.WorkflowRecord[] memory page, ) = registry
            .listActiveWorkflows(0, 100);

        assertEq(page.length, 2);
    }

    function testSetWorkflowActiveUnknownReverts() public {
        vm.prank(admin);

        vm.expectRevert(WorkflowRegistry.UnknownWorkflow.selector);
        registry.setWorkflowActive(999, false);
    }
}
