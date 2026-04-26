// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//******************************************************************************\
//* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
//* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
//*
//* Adapted from the CoreGameDiamond stack. Verbatim apart from:
//*   - removed the LibGameInfoStorage coupling inside isAuthorized so this lib
//*     can be shared by AgentDiamond (and future diamond types) without
//*     dragging in game-specific storage. Authorization beyond ownership now
//*     lives in the per-domain facets that need it (e.g. LibAgentPermissionStorage).
//******************************************************************************/

import {IDiamond} from "../interfaces/IDiamond.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {LibFacetRegistry} from "./LibFacetRegistry.sol";

error NoSelectorsGivenToAdd();
error NotContractOwner(address _user, address _contractOwner);
error NoSelectorsProvidedForFacetForCut(address _facetAddress);
error CannotAddSelectorsToZeroAddress(bytes4[] _selectors);
error NoBytecodeAtAddress(address _contractAddress, string _message);
error IncorrectFacetCutAction(uint8 _action);
error CannotAddFunctionToDiamondThatAlreadyExists(bytes4 _selector);
error CannotReplaceFunctionsFromFacetWithZeroAddress(bytes4[] _selectors);
error CannotReplaceImmutableFunction(bytes4 _selector);
error CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet(bytes4 _selector);
error CannotReplaceFunctionThatDoesNotExists(bytes4 _selector);
error RemoveFacetAddressMustBeZeroAddress(address _facetAddress);
error CannotRemoveFunctionThatDoesNotExist(bytes4 _selector);
error CannotRemoveImmutableFunction(bytes4 _selector);
error InitializationFunctionReverted(address _initializationContractAddress, bytes _calldata);

library LibDiamond {
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    struct FacetAddressAndSelectorPosition {
        address facetAddress;
        uint16 selectorPosition;
    }

    struct DiamondStorage {
        mapping(bytes4 => FacetAddressAndSelectorPosition) facetAddressAndSelectorPosition;
        bytes4[] selectors;
        mapping(bytes4 => bool) supportedInterfaces;
        address contractOwner;
    }

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setContractOwner(address _newOwner) internal {
        DiamondStorage storage ds = diamondStorage();
        ds.contractOwner = _newOwner;
    }

    function contractOwner() internal view returns (address) {
        return diamondStorage().contractOwner;
    }

    function enforceIsContractOwner() internal view {
        if (msg.sender != diamondStorage().contractOwner) {
            revert NotContractOwner(msg.sender, diamondStorage().contractOwner);
        }
    }

    event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);
    event DiamondCutName(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata, string[] _name);

    function diamondCutWithName(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata,
        string[] memory _name
    ) internal {
        if (_diamondCut.length != _name.length) {
            revert("FacetCut and name arrays must be the same length");
        }

        for (uint256 facetIndex = 0; facetIndex < _diamondCut.length; facetIndex++) {
            IDiamond.FacetCutAction action = _diamondCut[facetIndex].action;
            address localFacetAddress = _diamondCut[facetIndex].facetAddress;
            bytes4[] memory functionSelectors = _diamondCut[facetIndex].functionSelectors;

            if (functionSelectors.length == 0) {
                revert NoSelectorsProvidedForFacetForCut(localFacetAddress);
            }

            if (action == IDiamond.FacetCutAction.Add) {
                addFunctions(localFacetAddress, functionSelectors);
                LibFacetRegistry.registerFacet(localFacetAddress, _name[facetIndex]);
            } else if (action == IDiamond.FacetCutAction.Replace) {
                replaceFunctions(localFacetAddress, functionSelectors);
                LibFacetRegistry.updateFacet(localFacetAddress, _name[facetIndex]);
            } else if (action == IDiamond.FacetCutAction.Remove) {
                removeFunctions(localFacetAddress, functionSelectors);
                LibFacetRegistry.unregisterFacet(localFacetAddress);
            } else {
                revert IncorrectFacetCutAction(uint8(action));
            }
        }

        emit DiamondCutName(_diamondCut, _init, _calldata, _name);
        initializeDiamondCut(_init, _calldata);
    }

    function diamondCut(IDiamondCut.FacetCut[] memory _diamondCut, address _init, bytes memory _calldata) internal {
        for (uint256 facetIndex = 0; facetIndex < _diamondCut.length; facetIndex++) {
            IDiamond.FacetCutAction action = _diamondCut[facetIndex].action;
            address localFacetAddress = _diamondCut[facetIndex].facetAddress;
            bytes4[] memory functionSelectors = _diamondCut[facetIndex].functionSelectors;

            if (functionSelectors.length == 0) {
                revert NoSelectorsProvidedForFacetForCut(localFacetAddress);
            }

            if (action == IDiamond.FacetCutAction.Add) {
                addFunctions(localFacetAddress, functionSelectors);
            } else if (action == IDiamond.FacetCutAction.Replace) {
                replaceFunctions(localFacetAddress, functionSelectors);
            } else if (action == IDiamond.FacetCutAction.Remove) {
                removeFunctions(localFacetAddress, functionSelectors);
            } else {
                revert IncorrectFacetCutAction(uint8(action));
            }
        }

        emit DiamondCut(_diamondCut, _init, _calldata);
        initializeDiamondCut(_init, _calldata);
    }

    function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        if (_facetAddress == address(0)) {
            revert CannotAddSelectorsToZeroAddress(_functionSelectors);
        }

        DiamondStorage storage ds = diamondStorage();
        uint16 selectorCount = uint16(ds.selectors.length);
        enforceHasContractCode(_facetAddress, "LibDiamond: Add facet has no code");

        for (uint256 i = 0; i < _functionSelectors.length; i++) {
            bytes4 selector = _functionSelectors[i];
            if (ds.facetAddressAndSelectorPosition[selector].facetAddress != address(0)) {
                revert CannotAddFunctionToDiamondThatAlreadyExists(selector);
            }
            ds.facetAddressAndSelectorPosition[selector] = FacetAddressAndSelectorPosition(_facetAddress, selectorCount);
            ds.selectors.push(selector);
            selectorCount++;
        }
    }

    function replaceFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        if (_facetAddress == address(0)) {
            revert CannotReplaceFunctionsFromFacetWithZeroAddress(_functionSelectors);
        }

        DiamondStorage storage ds = diamondStorage();
        enforceHasContractCode(_facetAddress, "LibDiamond: Replace facet has no code");

        for (uint256 i = 0; i < _functionSelectors.length; i++) {
            bytes4 selector = _functionSelectors[i];
            address oldFacet = ds.facetAddressAndSelectorPosition[selector].facetAddress;

            if (oldFacet == address(0)) revert CannotReplaceFunctionThatDoesNotExists(selector);
            if (oldFacet == _facetAddress) revert CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet(selector);
            if (oldFacet == address(this)) revert CannotReplaceImmutableFunction(selector);

            ds.facetAddressAndSelectorPosition[selector].facetAddress = _facetAddress;
        }
    }

    function removeFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        if (_facetAddress != address(0)) {
            revert RemoveFacetAddressMustBeZeroAddress(_facetAddress);
        }

        DiamondStorage storage ds = diamondStorage();
        uint256 selectorCount = ds.selectors.length;

        for (uint256 i = 0; i < _functionSelectors.length; i++) {
            bytes4 selector = _functionSelectors[i];
            FacetAddressAndSelectorPosition memory old = ds.facetAddressAndSelectorPosition[selector];

            if (old.facetAddress == address(0)) revert CannotRemoveFunctionThatDoesNotExist(selector);
            if (old.facetAddress == address(this)) revert CannotRemoveImmutableFunction(selector);

            selectorCount--;
            if (old.selectorPosition != selectorCount) {
                bytes4 lastSelector = ds.selectors[selectorCount];
                ds.selectors[old.selectorPosition] = lastSelector;
                ds.facetAddressAndSelectorPosition[lastSelector].selectorPosition = old.selectorPosition;
            }

            ds.selectors.pop();
            delete ds.facetAddressAndSelectorPosition[selector];
        }
    }

    function initializeDiamondCut(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) return;

        enforceHasContractCode(_init, "LibDiamond: _init address has no code");

        (bool success, bytes memory error) = _init.delegatecall(_calldata);
        if (!success) {
            if (error.length > 0) {
                assembly {
                    let size := mload(error)
                    revert(add(error, 32), size)
                }
            } else {
                revert InitializationFunctionReverted(_init, _calldata);
            }
        }
    }

    function enforceHasContractCode(address _contract, string memory _msg) internal view {
        uint256 size;
        assembly {
            size := extcodesize(_contract)
        }
        if (size == 0) {
            revert NoBytecodeAtAddress(_contract, _msg);
        }
    }

    /// @notice Facet lookup by selector (used by Diamond fallback).
    function facetAddress(bytes4 _selector) internal view returns (address) {
        return diamondStorage().facetAddressAndSelectorPosition[_selector].facetAddress;
    }

    function supportsInterface(bytes4 interfaceId) internal view returns (bool) {
        return diamondStorage().supportedInterfaces[interfaceId];
    }
}
