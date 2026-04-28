// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Re-exported subset of the EIP-2535 standard so this bundle is self-contained.
interface IDiamond {
    enum FacetCutAction {
        Add,
        Replace,
        Remove
    }

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }
}
