// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAgentPermissionStorage} from "../libraries/LibAgentPermissionStorage.sol";
import {LibAgentManifestStorage} from "../libraries/LibAgentManifestStorage.sol";
import {IAgentPermission} from "../interfaces/IAgentPermission.sol";

contract AgentPermissionFacet is IAgentPermission {
    using LibAgentPermissionStorage for LibAgentPermissionStorage.Layout;

    // ---------------- ERRORS ----------------

    error ZeroAddress();
    error WorkflowFactoryNotSet();
    error NotWorkflowFactory();
    error NotWorkflowReady();
    error WorkflowFactoryAlreadySet();

    // ---------------- EVENTS ----------------

    event WorkflowFactorySet(address indexed factory);
    event WorkflowJoined(address indexed workflow, address indexed factory);

    // ---------------- MODIFIERS ----------------

    modifier onlyAdmin() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    // ---------------- FACTORY CONFIG ----------------

    function setWorkflowFactory(address _factory) external onlyAdmin {
        if (_factory == address(0)) revert ZeroAddress();

        LibAgentPermissionStorage.Layout storage s = LibAgentPermissionStorage
            .layout();

        if (s.workflowFactory != address(0)) {
            revert WorkflowFactoryAlreadySet();
        }

        s.workflowFactory = _factory;

        emit WorkflowFactorySet(_factory);
    }

    function getWorkflowFactory() external view returns (address) {
        return LibAgentPermissionStorage.layout().workflowFactory;
    }

    // ---------------- WORKFLOW JOIN ----------------

    function joinWorkflow(address workflow) external override {
        if (workflow == address(0)) revert ZeroAddress();

        LibAgentPermissionStorage.Layout storage s = LibAgentPermissionStorage
            .layout();

        if (s.workflowFactory == address(0)) {
            revert WorkflowFactoryNotSet();
        }

        // 🔴 FIX: allow factory OR owner
        if (
            msg.sender != s.workflowFactory &&
            msg.sender != LibDiamond.contractOwner()
        ) {
            revert NotWorkflowFactory();
        }

        LibAgentManifestStorage.Layout storage l = LibAgentManifestStorage
            .layout();

        if (!l.manifest.workflowReady) {
            revert NotWorkflowReady();
        }

        // ---------------- TRUST FACTORY ----------------

        if (!s.trustedCallers[s.workflowFactory]) {
            s.trustedCallers[s.workflowFactory] = true;
            s.trustedCallerList.push(s.workflowFactory);
            s.trustedCallerIndex[s.workflowFactory] = s
                .trustedCallerList
                .length;
        }

        // ---------------- TRUST WORKFLOW ----------------

        if (!s.trustedCallers[workflow]) {
            s.trustedCallers[workflow] = true;
            s.trustedCallerList.push(workflow);
            s.trustedCallerIndex[workflow] = s.trustedCallerList.length;
        }

        emit WorkflowJoined(workflow, msg.sender);
    }

    // ---------------- VIEW ----------------

    function isTrustedCaller(address account) external view returns (bool) {
        if (account == LibDiamond.contractOwner()) return true;

        return LibAgentPermissionStorage.layout().trustedCallers[account];
    }
}
