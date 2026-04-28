// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAgentManifestStorage} from "../libraries/LibAgentManifestStorage.sol";

contract AgentManifestFacet {
    using LibAgentManifestStorage for LibAgentManifestStorage.Layout;

    // ---------------------------------------------------------------------
    // EVENTS
    // ---------------------------------------------------------------------

    event ManifestInitialized(
        bytes32[] inputTypes,
        bytes32 outputType,
        uint256 costPerRequest,
        bytes32 manifestHash
    );

    event ManifestMetaUpdated(
        string name,
        string description,
        bytes32 manifestHash
    );
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event PayoutAddressUpdated(address oldPayout, address newPayout);
    event WorkflowReadyUpdated(bool ready);
    event PausedUpdated(bool paused);

    // ---------------------------------------------------------------------
    // ERRORS
    // ---------------------------------------------------------------------

    error AlreadyInitialized();
    error NotInitialized();
    error EmptyInputTypes();
    error ZeroAddress();

    // ---------------------------------------------------------------------
    // MODIFIERS
    // ---------------------------------------------------------------------

    modifier onlyAdmin() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    modifier onlyInitialized() {
        if (LibAgentManifestStorage.layout().manifest.createdAt == 0) {
            revert NotInitialized();
        }
        _;
    }

    // ---------------------------------------------------------------------
    // INITIALIZATION (SAFE BOOTSTRAP VERSION)
    // ---------------------------------------------------------------------

    /**
     * @notice One-time initializer
     * IMPORTANT:
     * - NO onlyAdmin here (bootstrap-safe)
     * - relies ONLY on "createdAt == 0"
     */
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

        emit ManifestInitialized(
            _inputTypes,
            _outputType,
            _costPerRequest,
            _manifestHash
        );
    }

    // ---------------------------------------------------------------------
    // ADMIN FUNCTIONS (SAFE AFTER INIT)
    // ---------------------------------------------------------------------

    function updateMeta(
        string calldata _name,
        string calldata _description,
        bytes32 _manifestHash
    ) external onlyAdmin onlyInitialized {
        LibAgentManifestStorage.AgentManifest
            storage m = LibAgentManifestStorage.layout().manifest;

        m.name = _name;
        m.description = _description;
        m.manifestHash = _manifestHash;
        m.updatedAt = uint64(block.timestamp);

        emit ManifestMetaUpdated(_name, _description, _manifestHash);
    }

    function setPrice(uint256 _newPrice) external onlyAdmin onlyInitialized {
        LibAgentManifestStorage.AgentManifest
            storage m = LibAgentManifestStorage.layout().manifest;

        uint256 old = m.costPerRequest;
        m.costPerRequest = _newPrice;
        m.updatedAt = uint64(block.timestamp);

        emit PriceUpdated(old, _newPrice);
    }

    function setPayoutAddress(
        address _newPayout
    ) external onlyAdmin onlyInitialized {
        if (_newPayout == address(0)) revert ZeroAddress();

        LibAgentManifestStorage.AgentManifest
            storage m = LibAgentManifestStorage.layout().manifest;

        address old = m.payoutAddress;
        m.payoutAddress = _newPayout;
        m.updatedAt = uint64(block.timestamp);

        emit PayoutAddressUpdated(old, _newPayout);
    }

    function setWorkflowReady(bool _ready) external onlyAdmin onlyInitialized {
        LibAgentManifestStorage.AgentManifest
            storage m = LibAgentManifestStorage.layout().manifest;

        m.workflowReady = _ready;
        m.updatedAt = uint64(block.timestamp);

        emit WorkflowReadyUpdated(_ready);
    }

    function setPaused(bool _paused) external onlyAdmin onlyInitialized {
        LibAgentManifestStorage.AgentManifest
            storage m = LibAgentManifestStorage.layout().manifest;

        m.paused = _paused;
        m.updatedAt = uint64(block.timestamp);

        emit PausedUpdated(_paused);
    }

    // ---------------------------------------------------------------------
    // READS
    // ---------------------------------------------------------------------

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
}
