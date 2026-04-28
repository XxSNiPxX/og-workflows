// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/oracles/MockERC7857Oracle.sol";

contract MockERC7857OracleTest is Test {
    MockERC7857Oracle oracle;

    address admin = address(1);
    address user1 = address(2);
    address other = address(3);

    function setUp() public {
        oracle = new MockERC7857Oracle(admin);
    }

    function _proof(
        bytes32 oldH,
        bytes32 newH,
        bytes memory key,
        address recipient
    ) internal pure returns (bytes memory) {
        return abi.encode(oldH, newH, key, recipient);
    }

    function testVerifyTransferProof() public {
        bytes memory proof = _proof(
            keccak256("old"),
            keccak256("new"),
            hex"ab",
            user1
        );

        IERC7857Oracle.PreimageProofOutput memory out = oracle
            .verifyTransferProof(proof);

        assertTrue(out.valid);
        assertEq(out.oldDataHash, keccak256("old"));
        assertEq(out.newDataHash, keccak256("new"));
        assertEq(out.recipient, user1);
    }

    function testVerifyCloneProof() public {
        bytes memory proof = _proof(
            keccak256("old"),
            keccak256("new"),
            hex"ab",
            user1
        );

        IERC7857Oracle.PreimageProofOutput memory out = oracle.verifyCloneProof(
            proof
        );

        assertTrue(out.valid);
    }

    function testAcceptAllFalse() public {
        vm.prank(admin);
        oracle.setAcceptAll(false);

        bytes memory proof = _proof(
            keccak256("old"),
            keccak256("new"),
            hex"ab",
            user1
        );

        IERC7857Oracle.PreimageProofOutput memory out = oracle
            .verifyTransferProof(proof);

        assertFalse(out.valid);
    }

    function testZeroRecipientInvalid() public {
        bytes memory proof = _proof(
            keccak256("old"),
            keccak256("new"),
            hex"ab",
            address(0)
        );

        IERC7857Oracle.PreimageProofOutput memory out = oracle
            .verifyTransferProof(proof);

        assertFalse(out.valid);
    }

    function testMalformedProofReverts() public {
        vm.expectRevert(MockERC7857Oracle.MalformedProof.selector);
        oracle.verifyTransferProof(hex"deadbeef");
    }

    function testAdminGuards() public {
        vm.expectRevert(MockERC7857Oracle.NotAdmin.selector);
        oracle.setAdmin(other);

        vm.expectRevert(MockERC7857Oracle.NotAdmin.selector);
        oracle.setAcceptAll(false);
    }
}
