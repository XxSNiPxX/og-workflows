// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LibAgentExecutionStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("agent.standard.execution.storage");

    enum RequestStatus {
        NONE,
        CREATED,
        PROCESSING,
        COMPLETED,
        FAILED,
        CANCELLED
    }

    struct RequestRecord {
        // identity / routing
        address workflow;        // address(0) for direct user requests in v1
        uint256 runId;
        uint256 stepIndex;
        // who & what
        address user;
        uint256 tokenId;         // user's iNFT
        bytes32 inputPointer;    // 0G storage pointer to input
        bytes32 inputType;
        bytes32 outputPointer;
        bytes32 outputType;
        bytes32 outputHash;      // integrity hash of output blob
        // bookkeeping
        RequestStatus status;
        uint64 createdAt;
        uint64 updatedAt;
    }

    struct Layout {
        // primary store, keyed by requestKey(workflow, runId, stepIndex)
        mapping(bytes32 => RequestRecord) requests;
        // enumeration helper
        bytes32[] requestKeys;
        // per-user enumeration
        mapping(address => bytes32[]) userRequests;
        // monotonic counter for direct-user requests (workflow == address(0))
        uint256 directRequestCounter;
        // configured ledger to write outputs to
        address userStateLedger;
        // configured iNFT contract for permission checks
        address userStateINFT;
    }

    function layout() internal pure returns (Layout storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    function requestKey(address workflow, uint256 runId, uint256 stepIndex)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(workflow, runId, stepIndex));
    }
}
