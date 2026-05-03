// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LibAgentManifestStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("agent.standard.manifest.storage.v1");

    struct AgentManifest {
        string name;
        string description;
        bytes32 manifestHash;
        bytes32[] inputTypes;
        bytes32 outputType;
        // economics (source of truth)
        uint256 costPerRequest;
        address payoutAddress;
        // execution flags
        bool workflowReady;
        bool paused;
        // timestamps
        uint64 createdAt;
        uint64 updatedAt;
    }

    struct Layout {
        AgentManifest manifest;
    }

    function layout() internal pure returns (Layout storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }
}
