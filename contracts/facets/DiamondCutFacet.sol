// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibFacetRegistryStorage} from "../libraries/LibFacetRegistryStorage.sol";

contract DiamondCutFacet is IDiamondCut {
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {
        LibDiamond.enforceIsContractOwner();
        IDiamondCut.FacetCut[] memory cuts = _diamondCut;
        LibDiamond.diamondCut(cuts, _init, _calldata);
    }

    /// @notice Convenience: diamondCut + simultaneously stamp the facet registry with names.
    /// @dev    Names are only registered for facet addresses we haven't seen before;
    ///         re-cuts don't overwrite an existing name.
    function diamondCutWithName(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata,
        string[] calldata facetNames
    ) external {
        LibDiamond.enforceIsContractOwner();
        require(_diamondCut.length == facetNames.length, "Mismatch");

        for (uint256 i = 0; i < _diamondCut.length; i++) {
            address facet = _diamondCut[i].facetAddress;
            string memory name = facetNames[i];

            LibFacetRegistryStorage.FacetRegistry storage s = LibFacetRegistryStorage.layout();
            if (bytes(s.facetNames[facet]).length == 0) {
                s.facetNames[facet] = name;
                s.nameToFacet[name] = facet;
                s.facetAddresses.push(facet);
            }
        }

        IDiamondCut.FacetCut[] memory cuts = _diamondCut;
        LibDiamond.diamondCut(cuts, _init, _calldata);
    }
}
