// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAgentManifestStorage} from "../libraries/LibAgentManifestStorage.sol";

contract AgentManifestFacet {
    using LibAgentManifestStorage for LibAgentManifestStorage.Layout;

    // ---------------- ERRORS ----------------

    error AlreadyInitialized();
    error NotInitialized();
    error EmptyInputTypes();
    error ZeroAddress();

    // ---------------- MODIFIERS ----------------

    modifier onlyAdmin() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    modifier onlyInitialized() {
        LibAgentManifestStorage.Layout storage l = LibAgentManifestStorage
            .layout();
        if (l.manifest.createdAt == 0) revert NotInitialized();
        _;
    }

    // ---------------- INIT ----------------

    function initManifest(
        string calldata _name,
        string calldata _description,
        bytes32 _manifestHash,
        bytes32[] calldata _inputTypes,
        bytes32 _outputType,
        uint256 _costPerRequest,
        address _payoutAddress,
        bool _workflowReady
    ) external {
        LibAgentManifestStorage.Layout storage l = LibAgentManifestStorage
            .layout();
        LibAgentManifestStorage.AgentManifest storage m = l.manifest;

        if (m.createdAt != 0) revert AlreadyInitialized();
        if (_inputTypes.length == 0) revert EmptyInputTypes();
        if (_payoutAddress == address(0)) revert ZeroAddress();

        m.name = _name;
        m.description = _description;
        m.manifestHash = _manifestHash;

        for (uint256 i = 0; i < _inputTypes.length; i++) {
            m.inputTypes.push(_inputTypes[i]);
        }

        m.outputType = _outputType;
        m.costPerRequest = _costPerRequest;
        m.payoutAddress = _payoutAddress;
        m.workflowReady = _workflowReady;
        m.paused = false;

        uint64 ts = uint64(block.timestamp);
        m.createdAt = ts;
        m.updatedAt = ts;
    }

    // ---------------- READ ----------------

    function getManifest()
        external
        view
        returns (LibAgentManifestStorage.AgentManifest memory)
    {
        return LibAgentManifestStorage.layout().manifest;
    }

    function getInputTypes() external view returns (bytes32[] memory) {
        return LibAgentManifestStorage.layout().manifest.inputTypes;
    }

    function getOutputType() external view returns (bytes32) {
        return LibAgentManifestStorage.layout().manifest.outputType;
    }

    function quote() external view returns (uint256) {
        return LibAgentManifestStorage.layout().manifest.costPerRequest;
    }

    function payoutAddress() external view returns (address) {
        return LibAgentManifestStorage.layout().manifest.payoutAddress;
    }

    function isPaused() external view returns (bool) {
        return LibAgentManifestStorage.layout().manifest.paused;
    }

    function isWorkflowReady() external view returns (bool) {
        return LibAgentManifestStorage.layout().manifest.workflowReady;
    }

    function supportsInput(bytes32 inputType) external view returns (bool) {
        bytes32[] storage ins = LibAgentManifestStorage
            .layout()
            .manifest
            .inputTypes;

        for (uint256 i = 0; i < ins.length; i++) {
            if (ins[i] == inputType) return true;
        }
        return false;
    }

    // ---------------- ADMIN ----------------

    function setPaused(bool _paused) external onlyAdmin onlyInitialized {
        LibAgentManifestStorage.layout().manifest.paused = _paused;
    }

    function setWorkflowReady(bool _ready) external onlyAdmin onlyInitialized {
        LibAgentManifestStorage.layout().manifest.workflowReady = _ready;
    }

    function setPayoutAddress(
        address _payout
    ) external onlyAdmin onlyInitialized {
        if (_payout == address(0)) revert ZeroAddress();
        LibAgentManifestStorage.layout().manifest.payoutAddress = _payout;
    }
}
