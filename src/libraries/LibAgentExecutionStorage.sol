// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LibAgentExecutionStorage {
    bytes32 constant STORAGE_POSITION = keccak256("agent.execution.storage");

    enum RequestStatus {
        NONE,
        CREATED,
        PROCESSING,
        COMPLETED,
        FAILED,
        CANCELLED
    }

    struct RequestRecord {
        address user;
        uint256 tokenId;
        address workflow;
        uint256 runId;
        uint256 stepIndex;
        bytes32 inputPointer;
        bytes32 inputType;
        bytes32 outputPointer;
        bytes32 outputType;
        bytes32 outputHash;
        RequestStatus status;
        uint64 createdAt;
        uint64 updatedAt;
    }

    struct Layout {
        mapping(bytes32 => RequestRecord) requests;
        // 🔴 deterministic queue
        bytes32[] pending;
        mapping(bytes32 => uint256) pendingIndex;
    }

    function layout() internal pure returns (Layout storage s) {
        bytes32 pos = STORAGE_POSITION;
        assembly {
            s.slot := pos
        }
    }

    function addPending(Layout storage s, bytes32 key) internal {
        s.pendingIndex[key] = s.pending.length;
        s.pending.push(key);
    }

    function removePending(Layout storage s, bytes32 key) internal {
        uint256 idx = s.pendingIndex[key];
        uint256 last = s.pending.length - 1;

        if (idx != last) {
            bytes32 lastKey = s.pending[last];
            s.pending[idx] = lastKey;
            s.pendingIndex[lastKey] = idx;
        }

        s.pending.pop();
        delete s.pendingIndex[key];
    }
}
