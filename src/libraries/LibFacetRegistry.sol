// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibFacetRegistryStorage} from "./LibFacetRegistryStorage.sol";

library LibFacetRegistry {
    event FacetRegistered(address indexed facet, string name);
    event FacetUnregistered(address indexed facet, string name);
    event FacetNameUpdated(address indexed facet, string oldName, string newName);
    event FacetOwnerUpdated(address indexed oldOwner, address indexed newOwner);

    function registerFacet(address facet, string memory name) internal {
        LibFacetRegistryStorage.FacetRegistry storage s = LibFacetRegistryStorage.layout();

        require(bytes(s.facetNames[facet]).length == 0, "Facet already registered");

        s.facetNames[facet] = name;
        s.nameToFacet[name] = facet;
        s.facetAddresses.push(facet);

        emit FacetRegistered(facet, name);
    }

    function updateFacet(address facet, string memory newName) internal {
        LibFacetRegistryStorage.FacetRegistry storage s = LibFacetRegistryStorage.layout();

        string memory oldName = s.facetNames[facet];

        if (bytes(oldName).length == 0) {
            s.facetNames[facet] = newName;
            s.nameToFacet[newName] = facet;
            s.facetAddresses.push(facet);
            emit FacetRegistered(facet, newName);
        } else {
            if (keccak256(bytes(oldName)) != keccak256(bytes(newName))) {
                delete s.nameToFacet[oldName];
                s.facetNames[facet] = newName;
                s.nameToFacet[newName] = facet;
                emit FacetNameUpdated(facet, oldName, newName);
            }
        }
    }

    function unregisterFacet(address facet) internal {
        LibFacetRegistryStorage.FacetRegistry storage s = LibFacetRegistryStorage.layout();

        string memory name = s.facetNames[facet];

        delete s.facetNames[facet];
        delete s.nameToFacet[name];

        uint256 len = s.facetAddresses.length;
        for (uint256 i = 0; i < len; i++) {
            if (s.facetAddresses[i] == facet) {
                s.facetAddresses[i] = s.facetAddresses[len - 1];
                s.facetAddresses.pop();
                break;
            }
        }

        emit FacetUnregistered(facet, name);
    }

    function getFacetName(address facet) internal view returns (string memory) {
        return LibFacetRegistryStorage.layout().facetNames[facet];
    }

    function getFacetAddress(string memory name) internal view returns (address) {
        return LibFacetRegistryStorage.layout().nameToFacet[name];
    }

    function getAllFacets() internal view returns (address[] memory) {
        return LibFacetRegistryStorage.layout().facetAddresses;
    }

    function updateOwner(address oldOwner, address newOwner) internal {
        emit FacetOwnerUpdated(oldOwner, newOwner);
    }
}
