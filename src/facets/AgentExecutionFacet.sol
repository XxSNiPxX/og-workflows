// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibAgentExecutionStorage} from "../libraries/LibAgentExecutionStorage.sol";
import {IWorkflowCallback} from "../interfaces/IWorkflowCallback.sol";

contract AgentExecutionFacet {
    using LibAgentExecutionStorage for LibAgentExecutionStorage.Layout;

    // ---------------- EVENTS ----------------

    event StepRequested(
        bytes32 indexed requestKey,
        uint256 runId,
        uint256 stepIndex,
        address user,
        uint256 tokenId,
        bytes32 inputPointer,
        bytes32 inputType,
        address workflow
    );

    // ---------------- CONFIG ----------------

    bytes32 constant CONFIG_SLOT = keccak256("agent.exec.config");

    function setExecutionConfig(address inft, address ledger) external {
        require(inft != address(0) && ledger != address(0), "bad");

        bytes32 slot = CONFIG_SLOT;
        assembly {
            sstore(slot, inft)
            sstore(add(slot, 1), ledger)
        }
    }

    function getExecutionConfig()
        external
        view
        returns (address inft, address ledger)
    {
        bytes32 slot = CONFIG_SLOT;
        assembly {
            inft := sload(slot)
            ledger := sload(add(slot, 1))
        }
    }

    // ---------------- REQUEST ----------------

    function request(
        address user,
        uint256 tokenId,
        bytes32 inputPointer,
        bytes32 inputType,
        uint256 runId,
        uint256 stepIndex
    ) external returns (bytes32 key) {
        LibAgentExecutionStorage.Layout storage s = LibAgentExecutionStorage
            .layout();

        key = keccak256(
            abi.encodePacked(user, tokenId, runId, stepIndex, block.timestamp)
        );

        s.requests[key] = LibAgentExecutionStorage.RequestRecord({
            user: user,
            tokenId: tokenId,
            workflow: msg.sender,
            runId: runId,
            stepIndex: stepIndex,
            inputPointer: inputPointer,
            inputType: inputType,
            outputPointer: 0,
            outputType: 0,
            outputHash: 0,
            status: LibAgentExecutionStorage.RequestStatus.CREATED,
            createdAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp)
        });

        s.addPending(key);

        emit StepRequested(
            key,
            runId,
            stepIndex,
            user,
            tokenId,
            inputPointer,
            inputType,
            msg.sender
        );
    }

    // ---------------- COMPLETE ----------------

    function complete(
        bytes32 key,
        bytes32 outputPointer,
        bytes32 outputType,
        bytes32 outputHash,
        bytes32,
        uint8
    ) external {
        LibAgentExecutionStorage.Layout storage s = LibAgentExecutionStorage
            .layout();

        LibAgentExecutionStorage.RequestRecord storage r = s.requests[key];

        require(
            r.status == LibAgentExecutionStorage.RequestStatus.CREATED ||
                r.status == LibAgentExecutionStorage.RequestStatus.PROCESSING,
            "bad state"
        );

        r.outputPointer = outputPointer;
        r.outputType = outputType;
        r.outputHash = outputHash;
        r.status = LibAgentExecutionStorage.RequestStatus.COMPLETED;
        r.updatedAt = uint64(block.timestamp);

        s.removePending(key);

        if (r.workflow != address(0)) {
            try
                IWorkflowCallback(r.workflow).onStepCompleted(
                    r.runId,
                    r.stepIndex,
                    outputPointer,
                    outputType,
                    outputHash
                )
            {} catch {}
        }
    }

    // ---------------- FAIL ----------------

    function fail(bytes32 key, bytes32 reasonHash) external {
        LibAgentExecutionStorage.Layout storage s = LibAgentExecutionStorage
            .layout();

        LibAgentExecutionStorage.RequestRecord storage r = s.requests[key];

        require(
            r.status == LibAgentExecutionStorage.RequestStatus.CREATED ||
                r.status == LibAgentExecutionStorage.RequestStatus.PROCESSING,
            "bad state"
        );

        r.status = LibAgentExecutionStorage.RequestStatus.FAILED;
        r.outputHash = reasonHash;
        r.updatedAt = uint64(block.timestamp);

        s.removePending(key);

        if (r.workflow != address(0)) {
            try
                IWorkflowCallback(r.workflow).onStepFailed(
                    r.runId,
                    r.stepIndex,
                    reasonHash
                )
            {} catch {}
        }
    }

    // ---------------- CANCEL ----------------

    function cancel(bytes32 key) external {
        LibAgentExecutionStorage.Layout storage s = LibAgentExecutionStorage
            .layout();

        LibAgentExecutionStorage.RequestRecord storage r = s.requests[key];

        require(
            r.status == LibAgentExecutionStorage.RequestStatus.CREATED ||
                r.status == LibAgentExecutionStorage.RequestStatus.PROCESSING,
            "bad state"
        );

        r.status = LibAgentExecutionStorage.RequestStatus.CANCELLED;
        r.updatedAt = uint64(block.timestamp);

        s.removePending(key);

        if (r.workflow != address(0)) {
            try
                IWorkflowCallback(r.workflow).onStepCancelled(
                    r.runId,
                    r.stepIndex
                )
            {} catch {}
        }
    }

    // ---------------- VIEW ----------------

    function getPendingRequests() external view returns (bytes32[] memory) {
        return LibAgentExecutionStorage.layout().pending;
    }

    function getRequest(
        bytes32 key
    ) external view returns (LibAgentExecutionStorage.RequestRecord memory) {
        return LibAgentExecutionStorage.layout().requests[key];
    }
}
