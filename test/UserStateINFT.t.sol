// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/UserStateINFT.sol";
import "../src/oracles/MockERC7857Oracle.sol";
import "../src/libraries/LibPermissionScope.sol";

contract UserStateINFTTest is Test {
    address inftAdmin = address(1);
    address oracleAdmin = address(2);
    address user1 = address(3);
    address user2 = address(4);
    address worker1 = address(5);
    address other = address(6);

    MockERC7857Oracle oracle;
    UserStateINFT inft;

    function setUp() public {
        vm.prank(oracleAdmin);
        oracle = new MockERC7857Oracle(oracleAdmin);

        vm.prank(inftAdmin);
        inft = new UserStateINFT(inftAdmin, address(oracle));
    }

    function H(string memory s) internal pure returns (bytes32) {
        return keccak256(bytes(s));
    }

    function encodeScope(
        bool canRead,
        bool canWrite,
        bool canAppend,
        bytes32[] memory types,
        uint256[] memory wf,
        uint64 expiresAt
    ) internal pure returns (bytes memory) {
        LibPermissionScope.PermissionScope memory s = LibPermissionScope
            .PermissionScope({
                canRead: canRead,
                canWrite: canWrite,
                canAppend: canAppend,
                allowedTypes: types,
                allowedWorkflowIds: wf,
                expiresAt: expiresAt
            });

        // ✅ critical: use library encode (keeps invariant)
        return LibPermissionScope.encode(s);
    }

    function defaultScope() internal pure returns (bytes memory) {
        bytes32[] memory types = new bytes32[](1);
        types[0] = H("type:result");

        uint256[] memory wf = new uint256[](1);
        wf[0] = 0;

        return encodeScope(true, true, true, types, wf, 0);
    }

    function setupToken() internal returns (uint256) {
        vm.prank(user1);
        inft.mint(user1, H("a"), hex"12", "uri");
        return 1;
    }

    function testMintBasic() public {
        vm.prank(user1);
        inft.mint(user1, H("a"), hex"1234", "ipfs://1");

        assertEq(inft.tokenIdOf(user1), 1);
        assertEq(inft.ownerOf(1), user1);
        assertEq(inft.dataHashOf(1), H("a"));
    }

    function testAuthorizeAndRevoke() public {
        uint256 tokenId = setupToken();

        vm.prank(user1);
        inft.authorizeUsage(tokenId, worker1, defaultScope());

        assertTrue(inft.isAuthorized(tokenId, worker1));

        vm.prank(user1);
        inft.revokeUsage(tokenId, worker1);

        assertFalse(inft.isAuthorized(tokenId, worker1));
    }

    function testSecureTransferClearsAuth() public {
        uint256 tokenId = setupToken();

        vm.prank(user1);
        inft.authorizeUsage(tokenId, worker1, defaultScope());

        bytes memory proof = abi.encode(H("a"), H("b"), hex"dead", user2);

        vm.prank(user1);
        inft.secureTransfer(user2, tokenId, proof);

        assertFalse(inft.isAuthorized(tokenId, worker1));
    }

    function testPublish() public {
        uint256 tokenId = setupToken();

        vm.prank(user1);
        inft.publish(tokenId, hex"dead");

        assertEq(inft.disclosedKeyOf(tokenId), hex"dead");
    }
}
