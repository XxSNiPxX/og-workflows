// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IUserStateLedger
/// @notice Append-only-ish ledger of user-owned state items, keyed by iNFT tokenId.
interface IUserStateLedger {
    enum Visibility {
        PUBLIC,
        ENCRYPTED,
        PRIVATE_SUMMARY
    }

    struct StateItem {
        bytes32 itemType;
        bytes32 pointer;       // 0G Storage pointer
        bytes32 contentHash;
        bytes32 labelHash;
        uint256 runId;
        uint256 stepIndex;
        Visibility visibility;
    }

    /// @notice Append a new state item to the user's ledger.
    /// @dev    Caller must be authorized in UserStateINFT for this tokenId
    ///         with a permission scope covering `item.itemType`.
    function appendItem(
        uint256 tokenId,
        address workflow,
        StateItem calldata item
    ) external returns (uint256);
}
