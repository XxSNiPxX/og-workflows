// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibDiamond} from "./libraries/LibDiamond.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";
import {IERC173} from "./interfaces/IERC173.sol";
import {IERC165} from "./interfaces/IERC165.sol";
import {InitialFaucets} from "./AgentDiamondShared.sol";

/// @title AgentDiamond
/// @notice Per-agent diamond proxy. Verbatim port of CoreGameDiamond:
///         same constructor shape, same fallback, same deployFacet hook,
///         same {owner, transferOwnership, supportsInterface} surface.
///
///         Domain facets (Manifest / Permission / Execution / Admin) are
///         attached by AgentFactory at deploy time.
contract AgentDiamond is IERC173, IERC165 {
    constructor(
        address _contractOwner,
        InitialFaucets[] memory _initalFaucets,
        IDiamondCut.FacetCut[] memory _facetCuts
    ) payable {
        LibDiamond.setContractOwner(_contractOwner);

        // Names parallel to _facetCuts. The factory builds these in lock-step.
        string[] memory names = new string[](_initalFaucets.length);
        for (uint256 i = 0; i < _initalFaucets.length; i++) {
            names[i] = _initalFaucets[i].name;
        }

        if (_facetCuts.length > 0) {
            LibDiamond.diamondCutWithName(_facetCuts, address(0), "", names);
        }
    }

    fallback() external payable {
        address facet = LibDiamond.facetAddress(msg.sig);
        require(facet != address(0), "Diamond: Function does not exist");

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {}

    /// @notice Owner-only dynamic facet attachment, mirrored from CoreGameDiamond.
    function deployFacet(
        IDiamondCut.FacetCut[] memory _facetCuts,
        string[] memory facetName
    ) external {
        require(msg.sender == LibDiamond.contractOwner(), "Only contract owner can deploy facets");
        if (_facetCuts.length > 0) {
            LibDiamond.diamondCutWithName(_facetCuts, address(0), "", facetName);
        }
    }

    function getSelectors() external view returns (bytes4[] memory) {
        return LibDiamond.diamondStorage().selectors;
    }

    function owner() external view override returns (address) {
        return LibDiamond.contractOwner();
    }

    function transferOwnership(address _newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        address previousOwner = LibDiamond.contractOwner();
        LibDiamond.setContractOwner(_newOwner);
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    function supportsInterface(bytes4 _interfaceId) external view override returns (bool) {
        return LibDiamond.supportsInterface(_interfaceId);
    }
}
