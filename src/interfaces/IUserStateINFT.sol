// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUserStateINFT {
    // --- ownership ---
    function ownerOf(uint256 tokenId) external view returns (address);

    function tokenIdOf(address wallet) external view returns (uint256);

    // --- permissions ---
    function isAuthorized(
        uint256 tokenId,
        address executor
    ) external view returns (bool);

    function isAuthorizedFor(
        uint256 tokenId,
        address executor,
        bytes32 itemType,
        uint256 workflowId
    ) external view returns (bool);

    function getPermissions(
        uint256 tokenId,
        address executor
    ) external view returns (bytes memory);

    // --- data ---
    function dataHashOf(uint256 tokenId) external view returns (bytes32);

    function encryptedURIOf(
        uint256 tokenId
    ) external view returns (string memory);

    function disclosedKeyOf(
        uint256 tokenId
    ) external view returns (bytes memory);
}
