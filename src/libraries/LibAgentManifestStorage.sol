// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LibAgentManifestStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("agent.standard.manifest.storage");

    struct AgentManifest {
        // identity
        string name;
        string description;
        bytes32 manifestHash;     // off-chain spec / system prompt hash
        // typing
        bytes32[] inputTypes;     // accepted input type identifiers
        bytes32 outputType;       // produced output type identifier
        // economics
        uint256 costPerRequest;   // wei (native 0G) per request
        address payoutAddress;    // where step payments land
        // ops
        bool workflowReady;       // opt-in for workflow composition
        bool paused;              // when true, request() reverts
        // versioning
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
