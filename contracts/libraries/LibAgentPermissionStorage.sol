// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library LibAgentPermissionStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("agent.standard.permission.storage");

    struct Layout {
        // The agent admin is canonically the diamond's contractOwner (LibDiamond),
        // so we don't duplicate it here. We track *workers* (off-chain processes
        // authorized to ack/complete/fail requests) and a *trustedCallers* set
        // (workflow contracts allowed to call request()).
        mapping(address => bool) workers;
        address[] workerList;
        mapping(address => uint256) workerIndex; // 1-based; 0 == not present

        mapping(address => bool) trustedCallers;
        address[] trustedCallerList;
        mapping(address => uint256) trustedCallerIndex;
    }

    function layout() internal pure returns (Layout storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }
}
