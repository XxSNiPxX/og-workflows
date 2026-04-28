// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title LibPermissionScope
/// @notice Typed encode/decode helpers for the `bytes permissions` blob that
///         travels through ERC-7857.authorizeUsage. We keep the on-wire format
///         opaque to ERC-7857 itself (per the standard) but standardise the
///         protocol-internal interpretation here.
library LibPermissionScope {
    struct PermissionScope {
        bool canRead;
        bool canWrite;
        bool canAppend;
        bytes32[] allowedTypes;        // empty array == any type allowed
        uint256[] allowedWorkflowIds;  // empty array == any workflow allowed
        uint64 expiresAt;              // 0 == never expires
    }

    /// @notice ABI-encode a scope for storage in UserStateINFT.
    function encode(PermissionScope memory scope) internal pure returns (bytes memory) {
        return abi.encode(scope);
    }

    /// @notice ABI-decode a scope previously stored via encode().
    /// @dev    Returns a zero-scope (`canRead=false`, etc.) for empty bytes
    ///         so callers can treat "never granted" and "explicitly deny-all"
    ///         identically.
    function decode(bytes memory data) internal pure returns (PermissionScope memory scope) {
        if (data.length == 0) {
            return scope; // zero-initialised
        }
        scope = abi.decode(data, (PermissionScope));
    }

    /// @notice Check whether a scope grants access for a given (itemType, workflowId)
    ///         and is not expired.
    function covers(
        PermissionScope memory scope,
        bytes32 itemType,
        uint256 workflowId
    ) internal view returns (bool) {
        if (scope.expiresAt != 0 && uint64(block.timestamp) > scope.expiresAt) {
            return false;
        }
        if (!_inTypes(scope.allowedTypes, itemType)) return false;
        if (!_inIds(scope.allowedWorkflowIds, workflowId)) return false;
        return true;
    }

    function _inTypes(bytes32[] memory list, bytes32 v) private pure returns (bool) {
        if (list.length == 0) return true; // wildcard
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == v) return true;
        }
        return false;
    }

    function _inIds(uint256[] memory list, uint256 v) private pure returns (bool) {
        if (list.length == 0) return true; // wildcard
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == v) return true;
        }
        return false;
    }
}
