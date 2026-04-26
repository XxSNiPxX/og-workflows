// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibFacetRegistryStorage} from "../libraries/LibFacetRegistryStorage.sol";

contract FacetRegistryFacet {
    event FacetRegistered(address indexed facet, string name);
    event FacetRemoved(address indexed facet, string name);

    function getFacetName(address facet) external view returns (string memory) {
        return LibFacetRegistryStorage.layout().facetNames[facet];
    }

    function getFacetAddress(string calldata name) external view returns (address) {
        return LibFacetRegistryStorage.layout().nameToFacet[name];
    }

    function getAllFacets() external view returns (address[] memory, string[] memory) {
        LibFacetRegistryStorage.FacetRegistry storage s = LibFacetRegistryStorage.layout();
        uint256 len = s.facetAddresses.length;

        address[] memory addresses = new address[](len);
        string[] memory names = new string[](len);

        for (uint256 i = 0; i < len; i++) {
            address facet = s.facetAddresses[i];
            addresses[i] = facet;
            names[i] = s.facetNames[facet];
        }

        return (addresses, names);
    }
}
