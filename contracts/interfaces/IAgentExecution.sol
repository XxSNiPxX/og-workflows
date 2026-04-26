// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAgentExecution
/// @notice The subset of AgentExecutionFacet that workflows interact with.
///         Read-side mirrors the storage record so workflows can poll state
///         when callbacks are missed.
interface IAgentExecution {
    enum RequestStatus { NONE, CREATED, PROCESSING, COMPLETED, FAILED, CANCELLED }

    struct RequestRecord {
        address workflow;
        uint256 runId;
        uint256 stepIndex;
        address user;
        uint256 tokenId;
        bytes32 inputPointer;
        bytes32 inputType;
        bytes32 outputPointer;
        bytes32 outputType;
        bytes32 outputHash;
        RequestStatus status;
        uint64 createdAt;
        uint64 updatedAt;
    }

    function request(
        address user,
        uint256 tokenId,
        bytes32 inputPointer,
        bytes32 inputType,
        uint256 runId,
        uint256 stepIndex
    ) external returns (bytes32 requestKey);

    function cancel(bytes32 requestKey) external;

    function getRequest(bytes32 requestKey) external view returns (RequestRecord memory);
}
