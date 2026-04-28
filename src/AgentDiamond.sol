// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibDiamond} from "./libraries/LibDiamond.sol";
import {IDiamond} from "./interfaces/IDiamond.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";
import {IERC173} from "./interfaces/IERC173.sol";
import {IERC165} from "./interfaces/IERC165.sol";

contract AgentDiamond is IERC173, IERC165 {
    constructor(address _owner, address _cutFacet) payable {
        require(_owner != address(0), "Owner zero");
        require(_cutFacet != address(0), "Cut facet zero");

        // set owner
        LibDiamond.setContractOwner(_owner);

        // wire ONLY diamondCut via proper diamondCut (so loupe sees it)
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IDiamondCut.diamondCut.selector;

        IDiamond.FacetCut[] memory cut = new IDiamond.FacetCut[](1);
        cut[0] = IDiamond.FacetCut({
            facetAddress: _cutFacet,
            action: IDiamond.FacetCutAction.Add,
            functionSelectors: selectors
        });

        LibDiamond.diamondCut(cut, address(0), "");
    }

    // =============================================================
    // FALLBACK
    // =============================================================

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

    // =============================================================
    // ERC-173 (ownership)
    // =============================================================

    function owner() external view override returns (address) {
        return LibDiamond.contractOwner();
    }

    function transferOwnership(address _newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        require(_newOwner != address(0), "Owner zero");

        address prev = LibDiamond.contractOwner();
        LibDiamond.setContractOwner(_newOwner);

        emit OwnershipTransferred(prev, _newOwner);
    }

    // =============================================================
    // ERC-165
    // =============================================================

    function supportsInterface(
        bytes4 interfaceId
    ) external view override returns (bool) {
        return LibDiamond.supportsInterface(interfaceId);
    }
}
