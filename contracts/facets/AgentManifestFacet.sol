// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAgentManifestStorage} from "../libraries/LibAgentManifestStorage.sol";

/// @title AgentManifestFacet
/// @notice Public-facing manifest for an agent diamond: name, description,
///         I/O types, price, payout address, workflow-readiness, paused state.
///
///         Admin-gated writes mirror the spec's `AgentManifest` struct. The
///         agent's *core interface* (inputTypes, outputType) is intentionally
///         NOT mutable post-init — per the spec, an interface change should be
///         a new agent version.
contract AgentManifestFacet {
    using LibAgentManifestStorage for LibAgentManifestStorage.Layout;

    event ManifestInitialized(
        bytes32[] inputTypes,
        bytes32 outputType,
        uint256 costPerRequest,
        bytes32 manifestHash
    );
    event ManifestMetaUpdated(string name, string description, bytes32 manifestHash);
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event PayoutAddressUpdated(address oldPayout, address newPayout);
    event WorkflowReadyUpdated(bool ready);
    event PausedUpdated(bool paused);

    error AlreadyInitialized();
    error NotInitialized();
    error EmptyInputTypes();
    error ZeroAddress();

    modifier onlyAdmin() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    // ---------------------------------------------------------------------
    // Initialization (called once during factory deployment via delegatecall)
    // ---------------------------------------------------------------------

    /// @notice One-shot initializer for the manifest. Must be called via the
    ///         diamond's init delegatecall during construction.
    function initManifest(
        string calldata _name,
        string calldata _description,
        bytes32 _manifestHash,
        bytes32[] calldata _inputTypes,
        bytes32 _outputType,
        uint256 _costPerRequest,
        address _payoutAddress,
        bool _workflowReady
    ) external onlyAdmin {
        LibAgentManifestStorage.AgentManifest storage m = LibAgentManifestStorage.layout().manifest;
        if (m.createdAt != 0) revert AlreadyInitialized();
        if (_inputTypes.length == 0) revert EmptyInputTypes();
        if (_payoutAddress == address(0)) revert ZeroAddress();

        m.name = _name;
        m.description = _description;
        m.manifestHash = _manifestHash;
        // copy bytes32[] calldata -> storage explicitly
        for (uint256 i = 0; i < _inputTypes.length; i++) {
            m.inputTypes.push(_inputTypes[i]);
        }
        m.outputType = _outputType;
        m.costPerRequest = _costPerRequest;
        m.payoutAddress = _payoutAddress;
        m.workflowReady = _workflowReady;
        m.paused = false;
        m.createdAt = uint64(block.timestamp);
        m.updatedAt = uint64(block.timestamp);

        emit ManifestInitialized(_inputTypes, _outputType, _costPerRequest, _manifestHash);
    }

    // ---------------------------------------------------------------------
    // Admin mutations
    // ---------------------------------------------------------------------

    function updateMeta(
        string calldata _name,
        string calldata _description,
        bytes32 _manifestHash
    ) external onlyAdmin {
        LibAgentManifestStorage.AgentManifest storage m = LibAgentManifestStorage.layout().manifest;
        if (m.createdAt == 0) revert NotInitialized();
        m.name = _name;
        m.description = _description;
        m.manifestHash = _manifestHash;
        m.updatedAt = uint64(block.timestamp);
        emit ManifestMetaUpdated(_name, _description, _manifestHash);
    }

    function setPrice(uint256 _newPrice) external onlyAdmin {
        LibAgentManifestStorage.AgentManifest storage m = LibAgentManifestStorage.layout().manifest;
        if (m.createdAt == 0) revert NotInitialized();
        uint256 old = m.costPerRequest;
        m.costPerRequest = _newPrice;
        m.updatedAt = uint64(block.timestamp);
        emit PriceUpdated(old, _newPrice);
    }

    function setPayoutAddress(address _newPayout) external onlyAdmin {
        if (_newPayout == address(0)) revert ZeroAddress();
        LibAgentManifestStorage.AgentManifest storage m = LibAgentManifestStorage.layout().manifest;
        if (m.createdAt == 0) revert NotInitialized();
        address old = m.payoutAddress;
        m.payoutAddress = _newPayout;
        m.updatedAt = uint64(block.timestamp);
        emit PayoutAddressUpdated(old, _newPayout);
    }

    function setWorkflowReady(bool _ready) external onlyAdmin {
        LibAgentManifestStorage.AgentManifest storage m = LibAgentManifestStorage.layout().manifest;
        if (m.createdAt == 0) revert NotInitialized();
        m.workflowReady = _ready;
        m.updatedAt = uint64(block.timestamp);
        emit WorkflowReadyUpdated(_ready);
    }

    function setPaused(bool _paused) external onlyAdmin {
        LibAgentManifestStorage.AgentManifest storage m = LibAgentManifestStorage.layout().manifest;
        if (m.createdAt == 0) revert NotInitialized();
        m.paused = _paused;
        m.updatedAt = uint64(block.timestamp);
        emit PausedUpdated(_paused);
    }

    // ---------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------

    function getManifest() external view returns (LibAgentManifestStorage.AgentManifest memory) {
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

    function isPaused() external view returns (bool) {
        return LibAgentManifestStorage.layout().manifest.paused;
    }

    function isWorkflowReady() external view returns (bool) {
        return LibAgentManifestStorage.layout().manifest.workflowReady;
    }

    function supportsInput(bytes32 inputType) external view returns (bool) {
        bytes32[] storage ins = LibAgentManifestStorage.layout().manifest.inputTypes;
        for (uint256 i = 0; i < ins.length; i++) {
            if (ins[i] == inputType) return true;
        }
        return false;
    }
}
