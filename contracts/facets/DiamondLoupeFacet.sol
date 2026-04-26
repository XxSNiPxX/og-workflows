// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDiamondLoupe} from "../interfaces/IDiamondLoupe.sol";
import {IERC165} from "../interfaces/IERC165.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

contract DiamondLoupeFacet is IDiamondLoupe, IERC165 {
    /// @notice Gets all facets and their selectors.
    function facets() external view override returns (Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 selectorCount = ds.selectors.length;

        // first pass: discover unique facet addresses
        address[] memory uniqueFacets = new address[](selectorCount);
        uint256 uniqueCount;

        for (uint256 i = 0; i < selectorCount; i++) {
            address facet = ds.facetAddressAndSelectorPosition[ds.selectors[i]].facetAddress;
            bool seen;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (uniqueFacets[j] == facet) { seen = true; break; }
            }
            if (!seen) {
                uniqueFacets[uniqueCount] = facet;
                uniqueCount++;
            }
        }

        // second pass: collect selectors per facet
        facets_ = new Facet[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            address f = uniqueFacets[i];
            uint256 count;
            for (uint256 j = 0; j < selectorCount; j++) {
                if (ds.facetAddressAndSelectorPosition[ds.selectors[j]].facetAddress == f) {
                    count++;
                }
            }
            bytes4[] memory selectorsForFacet = new bytes4[](count);
            uint256 idx;
            for (uint256 j = 0; j < selectorCount; j++) {
                bytes4 sel = ds.selectors[j];
                if (ds.facetAddressAndSelectorPosition[sel].facetAddress == f) {
                    selectorsForFacet[idx++] = sel;
                }
            }
            facets_[i] = Facet({ facetAddress: f, functionSelectors: selectorsForFacet });
        }
    }

    function facetFunctionSelectors(address _facet)
        external
        view
        override
        returns (bytes4[] memory selectors_)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 selectorCount = ds.selectors.length;

        uint256 count;
        for (uint256 i = 0; i < selectorCount; i++) {
            if (ds.facetAddressAndSelectorPosition[ds.selectors[i]].facetAddress == _facet) {
                count++;
            }
        }
        selectors_ = new bytes4[](count);
        uint256 idx;
        for (uint256 i = 0; i < selectorCount; i++) {
            bytes4 sel = ds.selectors[i];
            if (ds.facetAddressAndSelectorPosition[sel].facetAddress == _facet) {
                selectors_[idx++] = sel;
            }
        }
    }

    function facetAddresses() external view override returns (address[] memory addresses_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 selectorCount = ds.selectors.length;

        address[] memory tmp = new address[](selectorCount);
        uint256 unique;
        for (uint256 i = 0; i < selectorCount; i++) {
            address f = ds.facetAddressAndSelectorPosition[ds.selectors[i]].facetAddress;
            bool seen;
            for (uint256 j = 0; j < unique; j++) {
                if (tmp[j] == f) { seen = true; break; }
            }
            if (!seen) { tmp[unique++] = f; }
        }
        addresses_ = new address[](unique);
        for (uint256 i = 0; i < unique; i++) addresses_[i] = tmp[i];
    }

    function facetAddress(bytes4 _functionSelector) external view override returns (address) {
        return LibDiamond.diamondStorage().facetAddressAndSelectorPosition[_functionSelector].facetAddress;
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return LibDiamond.supportsInterface(interfaceId)
            || interfaceId == type(IDiamondLoupe).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
