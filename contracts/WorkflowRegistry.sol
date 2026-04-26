// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IWorkflowRegistry} from "./interfaces/IWorkflowRegistry.sol";

/// @title WorkflowRegistry
/// @notice Global, append-only index of every workflow deployed via WorkflowFactory.
///         Mirrors the snapshot fields needed for discovery; the live state
///         (per-run progress, escrow balances) lives on the WorkflowInstance.
contract WorkflowRegistry is IWorkflowRegistry {
    address public factory;
    address public admin;
    bool public registryPaused;

    uint256 public nextWorkflowId;
    mapping(uint256 => WorkflowRecord) internal _workflows;
    mapping(address => uint256) public workflowIdByAddress;
    mapping(address => uint256[]) internal _workflowsByCreator;

    uint256[] internal _allWorkflowIds;

    event FactorySet(address indexed factory);
    event AdminSet(address indexed admin);
    event RegistryPaused(bool paused);

    error NotFactory();
    error NotAdmin();
    error ZeroAddress();
    error AlreadyRegistered();
    error UnknownWorkflow();
    error Paused();

    constructor(address _admin) {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
        emit AdminSet(_admin);
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    function setFactory(address _factory) external onlyAdmin {
        if (_factory == address(0)) revert ZeroAddress();
        factory = _factory;
        emit FactorySet(_factory);
    }

    function setAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
        emit AdminSet(_admin);
    }

    function setPaused(bool _paused) external onlyAdmin {
        registryPaused = _paused;
        emit RegistryPaused(_paused);
    }

    function registerWorkflow(RegisterParams calldata p)
        external
        override
        returns (uint256 workflowId)
    {
        if (msg.sender != factory) revert NotFactory();
        if (registryPaused) revert Paused();
        if (p.workflowAddress == address(0)) revert ZeroAddress();
        if (workflowIdByAddress[p.workflowAddress] != 0) revert AlreadyRegistered();

        workflowId = ++nextWorkflowId;
        WorkflowRecord storage rec = _workflows[workflowId];
        rec.workflowId = workflowId;
        rec.workflowAddress = p.workflowAddress;
        rec.creator = p.creator;
        rec.inputType = p.inputType;
        rec.outputType = p.outputType;
        rec.totalCost = p.totalCost;
        rec.stepCount = p.stepCount;
        rec.active = true;
        rec.createdAt = uint64(block.timestamp);
        rec.name = p.name;
        rec.description = p.description;

        workflowIdByAddress[p.workflowAddress] = workflowId;
        _workflowsByCreator[p.creator].push(workflowId);
        _allWorkflowIds.push(workflowId);

        emit WorkflowRegistered(workflowId, p.workflowAddress, p.creator);
    }

    function setWorkflowActive(uint256 workflowId, bool active_) external onlyAdmin {
        WorkflowRecord storage rec = _workflows[workflowId];
        if (rec.workflowAddress == address(0)) revert UnknownWorkflow();
        rec.active = active_;
        emit WorkflowActiveSet(workflowId, active_);
    }

    function getWorkflow(uint256 workflowId) external view returns (WorkflowRecord memory) {
        return _workflows[workflowId];
    }

    function getWorkflowByAddress(address workflowAddress) external view returns (WorkflowRecord memory) {
        return _workflows[workflowIdByAddress[workflowAddress]];
    }

    function listWorkflowsByCreator(address creator, uint256 cursor, uint256 limit)
        external
        view
        returns (WorkflowRecord[] memory page, uint256 nextCursor)
    {
        return _paginate(_workflowsByCreator[creator], cursor, limit, false);
    }

    function listAllWorkflows(uint256 cursor, uint256 limit)
        external
        view
        returns (WorkflowRecord[] memory page, uint256 nextCursor)
    {
        return _paginate(_allWorkflowIds, cursor, limit, false);
    }

    function listActiveWorkflows(uint256 cursor, uint256 limit)
        external
        view
        returns (WorkflowRecord[] memory page, uint256 nextCursor)
    {
        return _paginate(_allWorkflowIds, cursor, limit, true);
    }

    function totalWorkflows() external view returns (uint256) {
        return _allWorkflowIds.length;
    }

    function _paginate(
        uint256[] storage ids,
        uint256 cursor,
        uint256 limit,
        bool activeOnly
    ) internal view returns (WorkflowRecord[] memory page, uint256 nextCursor) {
        if (cursor >= ids.length) return (new WorkflowRecord[](0), ids.length);
        uint256 end = cursor + limit;
        if (end > ids.length) end = ids.length;

        uint256 keep = end - cursor;
        if (activeOnly) {
            keep = 0;
            for (uint256 i = cursor; i < end; i++) {
                if (_workflows[ids[i]].active) keep++;
            }
        }

        page = new WorkflowRecord[](keep);
        uint256 j;
        for (uint256 i = cursor; i < end; i++) {
            WorkflowRecord storage rec = _workflows[ids[i]];
            if (activeOnly && !rec.active) continue;
            page[j++] = rec;
        }
        nextCursor = end;
    }
}
