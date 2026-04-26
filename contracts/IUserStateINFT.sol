// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IUserStateINFT
/// @notice Protocol-specific surface of the UserStateINFT contract,
///         used by AgentDiamond / WorkflowInstance / UserStateLedger
///         to check authorization and ownership.
interface IUserStateINFT {
    /// @notice Look up the primary tokenId for a wallet (0 if none).
    function tokenIdOf(address wallet) external view returns (uint256);

    /// @notice ERC-721 owner.
    function ownerOf(uint256 tokenId) external view returns (address);

    /// @notice Returns true if `executor` has a non-expired authorization
    ///         covering the given `itemType` and `workflowId`.
    /// @dev    `workflowId == 0` means "no workflow scope" (single-agent use).
    function isAuthorizedFor(
        uint256 tokenId,
        address executor,
        bytes32 itemType,
        uint256 workflowId
    ) external view returns (bool);
}
