// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../src/interfaces/IAgent.sol";
import "../../src/interfaces/IAgentExecution.sol";
import "../../src/interfaces/IWorkflowInstance.sol";

contract MockAgent is IAgent, IAgentExecution {
    bytes32 public inputType;
    bytes32 public outputType;
    uint256 public price;
    address public payout;

    uint256 public counter;

    mapping(bytes32 => RequestRecord) public requests;
    mapping(address => bool) public trustedCallers;

    constructor(bytes32 _in, bytes32 _out, uint256 _price, address _payout) {
        inputType = _in;
        outputType = _out;
        price = _price;
        payout = _payout;
    }

    // ===== IAgent =====

    function isWorkflowReady() external pure override returns (bool) {
        return true;
    }

    function isPaused() external pure override returns (bool) {
        return false;
    }

    function supportsInput(bytes32 t) external view override returns (bool) {
        return t == inputType;
    }

    function getOutputType() external view override returns (bytes32) {
        return outputType;
    }

    function quote() external view override returns (uint256) {
        return price;
    }

    function payoutAddress() external view override returns (address) {
        return payout;
    }

    function joinWorkflow(address wf) external override {
        trustedCallers[wf] = true;
    }

    function isTrustedCaller(address wf) external view returns (bool) {
        return trustedCallers[wf];
    }

    // ===== IAgentExecution =====

    function request(
        address user,
        uint256 tokenId,
        bytes32 inputPointer,
        bytes32 inputType_,
        uint256 runId,
        uint256 stepIndex
    ) external override returns (bytes32 key) {
        key = keccak256(abi.encode(++counter));

        requests[key] = RequestRecord({
            workflow: msg.sender,
            runId: runId,
            stepIndex: stepIndex,
            user: user,
            tokenId: tokenId,
            inputPointer: inputPointer,
            inputType: inputType_,
            outputPointer: bytes32(0),
            outputType: bytes32(0),
            outputHash: bytes32(0),
            status: RequestStatus.CREATED,
            createdAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp)
        });
    }

    function cancel(bytes32 key) external override {
        RequestRecord storage r = requests[key];
        r.status = RequestStatus.CANCELLED;

        IWorkflowInstance(r.workflow).onStepCancelled(r.runId, r.stepIndex);
    }

    function getRequest(
        bytes32 key
    ) external view override returns (RequestRecord memory) {
        return requests[key];
    }
}
