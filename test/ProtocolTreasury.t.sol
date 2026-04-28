// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ProtocolTreasury.sol";

contract ProtocolTreasuryTest is Test {
    ProtocolTreasury treasury;

    address treasuryAdmin = address(1);
    address feeRecipient = address(2);

    address factoryFake = address(3);
    address workflow = address(4);

    address user1 = address(10);
    address payout = address(11);

    // ---------------------------------------------------------
    // SETUP
    // ---------------------------------------------------------

    function setUp() public {
        treasury = new ProtocolTreasury(treasuryAdmin, feeRecipient, 0);

        // Give all actors ETH
        vm.deal(workflow, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(payout, 1 ether);
        vm.deal(feeRecipient, 1 ether);
    }

    function _setupWorkflow() internal {
        vm.prank(treasuryAdmin);
        treasury.setFactory(factoryFake);

        vm.prank(factoryFake);
        treasury.registerWorkflow(workflow);

        assertTrue(treasury.isRegistered(workflow));
    }

    function _deposit() internal {
        _setupWorkflow();

        vm.prank(workflow);
        treasury.deposit{value: 3 ether}(1, user1);

        assertEq(treasury.balanceOf(workflow, 1), 3 ether);
    }

    // ---------------------------------------------------------
    // DEPOSIT
    // ---------------------------------------------------------

    function testDeposit() public {
        vm.expectRevert(ProtocolTreasury.NotRegisteredWorkflow.selector);
        treasury.deposit{value: 1 ether}(1, user1);

        _setupWorkflow();

        vm.prank(workflow);
        vm.expectRevert(ProtocolTreasury.ZeroAmount.selector);
        treasury.deposit{value: 0}(1, user1);

        vm.prank(workflow);
        treasury.deposit{value: 2 ether}(1, user1);

        assertEq(treasury.balanceOf(workflow, 1), 2 ether);

        ProtocolTreasury.Escrow memory e = treasury.getEscrow(workflow, 1);
        assertEq(e.deposited, 2 ether);
        assertEq(e.payer, user1);
        assertEq(uint256(e.status), 1);

        vm.prank(workflow);
        vm.expectRevert(ProtocolTreasury.AlreadyExists.selector);
        treasury.deposit{value: 1 ether}(1, user1);
    }

    // ---------------------------------------------------------
    // RELEASE / REFUND / SETTLE
    // ---------------------------------------------------------

    function testReleaseAndRefund() public {
        _deposit();

        uint256 payoutBefore = payout.balance;
        uint256 userBefore = user1.balance;

        vm.prank(workflow);
        treasury.releaseTo(1, payout, 1 ether);

        assertEq(payout.balance, payoutBefore + 1 ether);
        assertEq(treasury.balanceOf(workflow, 1), 2 ether);

        vm.prank(workflow);
        treasury.refundTo(1, user1, 1 ether);

        assertEq(user1.balance, userBefore + 1 ether);
        assertEq(treasury.balanceOf(workflow, 1), 1 ether);
    }

    function testReleaseWithFee() public {
        _deposit();

        vm.prank(treasuryAdmin);
        treasury.setFeeBps(1000); // 10%

        uint256 payoutBefore = payout.balance;
        uint256 feeBefore = feeRecipient.balance;

        vm.prank(workflow);
        treasury.releaseTo(1, payout, 1 ether);

        assertEq(payout.balance, payoutBefore + 0.9 ether);
        assertEq(feeRecipient.balance, feeBefore + 0.1 ether);
        assertEq(treasury.totalFeesCollected(), 0.1 ether);
    }

    function testSettle() public {
        _deposit();

        vm.prank(workflow);
        treasury.releaseTo(1, payout, 1 ether);

        uint256 userBefore = user1.balance;

        vm.prank(workflow);
        treasury.settle(1, user1);

        assertEq(user1.balance, userBefore + 2 ether);

        ProtocolTreasury.Escrow memory e = treasury.getEscrow(workflow, 1);
        assertEq(uint256(e.status), 2);

        vm.prank(workflow);
        vm.expectRevert(ProtocolTreasury.EscrowNotActive.selector);
        treasury.settle(1, user1);
    }

    // ---------------------------------------------------------
    // RECEIVE
    // ---------------------------------------------------------

    function testReceiveReverts() public {
        vm.prank(user1);
        vm.expectRevert();
        payable(address(treasury)).transfer(1 ether);
    }
}
