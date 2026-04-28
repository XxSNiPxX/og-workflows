// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/UserStateLedger.sol";
import "../src/UserStateINFT.sol";
import "../src/oracles/MockERC7857Oracle.sol";
import "../src/libraries/LibPermissionScope.sol";
import "../src/interfaces/IUserStateLedger.sol";

contract UserStateLedgerTest is Test {
    UserStateLedger ledger;
    UserStateINFT inft;
    MockERC7857Oracle oracle;

    address inftAdmin = address(1);
    address oracleAdmin = address(2);
    address user1 = address(3);
    address user2 = address(4);
    address worker1 = address(5);
    address other = address(6);

    function H(string memory s) internal pure returns (bytes32) {
        return keccak256(bytes(s));
    }

    // =============================================================
    // SETUP
    // =============================================================

    function setUp() public {
        vm.prank(oracleAdmin);
        oracle = new MockERC7857Oracle(oracleAdmin);

        vm.prank(inftAdmin);
        inft = new UserStateINFT(inftAdmin, address(oracle));

        ledger = new UserStateLedger(address(inft));

        vm.prank(user1);
        inft.mint(user1, H("u1"), hex"12", "uri1");

        vm.prank(user2);
        inft.mint(user2, H("u2"), hex"12", "uri2");
    }

    // =============================================================
    // HELPERS
    // =============================================================

    function defaultScope() internal pure returns (bytes memory) {
        bytes32[] memory types = new bytes32[](1);
        types[0] = keccak256("type:result");

        uint256[] memory wf = new uint256[](1);
        wf[0] = 0;

        LibPermissionScope.PermissionScope memory s = LibPermissionScope
            .PermissionScope({
                canRead: true,
                canWrite: true,
                canAppend: true,
                allowedTypes: types,
                allowedWorkflowIds: wf,
                expiresAt: 0
            });

        return LibPermissionScope.encode(s);
    }

    function makeItem()
        internal
        pure
        returns (IUserStateLedger.StateItem memory)
    {
        return
            IUserStateLedger.StateItem({
                itemType: keccak256("type:result"),
                pointer: keccak256("ptr"),
                contentHash: keccak256("hash"),
                labelHash: keccak256("label"),
                runId: 0,
                stepIndex: 0,
                visibility: IUserStateLedger.Visibility.PUBLIC
            });
    }

    // =============================================================
    // CONSTRUCTOR
    // =============================================================

    function testConstructorStoresINFT() public view {
        assertEq(address(ledger.inft()), address(inft));
    }

    function testConstructorRejectsZero() public {
        vm.expectRevert(UserStateLedger.ZeroAddress.selector);
        new UserStateLedger(address(0));
    }

    // =============================================================
    // AUTHORIZATION
    // =============================================================

    function testOwnerCanAppend() public {
        vm.prank(user1);
        ledger.appendItem(1, address(0), makeItem());

        assertEq(ledger.totalItems(1), 1);
    }

    function testNonOwnerWithoutAuthReverts() public {
        vm.expectRevert(UserStateLedger.WriterNotAuthorized.selector);

        vm.prank(other);
        ledger.appendItem(1, address(0), makeItem());
    }

    function testAuthorizedAgentCanAppend() public {
        vm.prank(user1);
        inft.authorizeUsage(1, worker1, defaultScope());

        vm.prank(worker1);
        ledger.appendItem(1, address(0), makeItem());

        assertEq(ledger.totalItems(1), 1);
    }

    function testWrongTypeReverts() public {
        bytes32[] memory types = new bytes32[](1);
        types[0] = keccak256("type:other");

        uint256[] memory wf = new uint256[](1);
        wf[0] = 0;

        LibPermissionScope.PermissionScope memory s = LibPermissionScope
            .PermissionScope({
                canRead: true,
                canWrite: true,
                canAppend: true,
                allowedTypes: types,
                allowedWorkflowIds: wf,
                expiresAt: 0
            });

        vm.prank(user1);
        inft.authorizeUsage(1, worker1, LibPermissionScope.encode(s));

        vm.expectRevert(UserStateLedger.WriterNotAuthorized.selector);

        vm.prank(worker1);
        ledger.appendItem(1, address(0), makeItem());
    }

    function testWorkflowAuth() public {
        address wf = address(0x1111111111111111111111111111111111111111);

        uint256[] memory wfIds = new uint256[](1);
        wfIds[0] = uint256(uint160(wf));

        LibPermissionScope.PermissionScope memory s = LibPermissionScope
            .PermissionScope({
                canRead: true,
                canWrite: true,
                canAppend: true,
                allowedTypes: new bytes32[](0),
                allowedWorkflowIds: wfIds,
                expiresAt: 0
            });

        vm.prank(user1);
        inft.authorizeUsage(1, wf, LibPermissionScope.encode(s));

        vm.prank(worker1);
        ledger.appendItem(1, wf, makeItem());

        assertEq(ledger.totalItems(1), 1);
    }

    // =============================================================
    // INDEXING
    // =============================================================

    function testItemIdsIncrement() public {
        vm.prank(user1);
        ledger.appendItem(1, address(0), makeItem());

        vm.prank(user1);
        ledger.appendItem(1, address(0), makeItem());

        assertEq(ledger.getItem(1, 0).itemId, 0);
        assertEq(ledger.getItem(1, 1).itemId, 1);
    }

    // =============================================================
    // OWNER MUTATIONS
    // =============================================================

    function testArchiveOnlyOwner() public {
        vm.prank(user1);
        ledger.appendItem(1, address(0), makeItem());

        vm.expectRevert(UserStateLedger.NotTokenOwner.selector);
        vm.prank(other);
        ledger.archiveItem(1, 0, true);

        vm.prank(user1);
        ledger.archiveItem(1, 0, true);

        assertTrue(ledger.getItem(1, 0).archived);
    }

    function testUpdatePointer() public {
        vm.prank(user1);
        ledger.appendItem(1, address(0), makeItem());

        vm.prank(user1);
        ledger.updateItemPointer(1, 0, H("new"), H("newhash"));

        UserStateLedger.StoredItem memory it = ledger.getItem(1, 0);

        assertEq(it.pointer, H("new"));
        assertEq(it.contentHash, H("newhash"));
    }
}
