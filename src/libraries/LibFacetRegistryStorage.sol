// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LibFacetRegistryStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("diamond.coregame.facet.registry");

    struct FacetRegistry {
        mapping(address => string) facetNames;
        mapping(string => address) nameToFacet;
        address[] facetAddresses;
    }

    function layout() internal pure returns (FacetRegistry storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }
}
