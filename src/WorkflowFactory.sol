// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {WorkflowInstance} from "./WorkflowInstance.sol";
import {WorkflowRegistry} from "./WorkflowRegistry.sol";
import {ProtocolTreasury} from "./ProtocolTreasury.sol";
import {IWorkflowInstance} from "./interfaces/IWorkflowInstance.sol";
import {IWorkflowRegistry} from "./interfaces/IWorkflowRegistry.sol";
import {IAgent} from "./interfaces/IAgent.sol";

contract WorkflowFactory {
    WorkflowRegistry public immutable registry;
    ProtocolTreasury public immutable treasury;

    address public immutable userStateINFT;
    address public immutable userStateLedger; // ✅ NEW

    address public protocolAdmin;

    mapping(address => address[]) public creatorToWorkflows;
    address[] public allWorkflows;

    // -----------------------------------------------------

    error ZeroAddress();
    error EmptyWorkflow();
    error AgentZeroAddress(uint256 i);
    error AgentNotWorkflowReady(uint256 i, address a);
    error AgentPaused(uint256 i, address a);
    error AgentDoesNotSupportInput(uint256 i, address a, bytes32 t);
    error TypeChainBroken(uint256 i, bytes32 expected, bytes32 got);

    // -----------------------------------------------------

    constructor(
        address _registry,
        address _treasury,
        address _userStateINFT,
        address _userStateLedger, // ✅ NEW
        address _protocolAdmin
    ) {
        if (_registry == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();
        if (_userStateINFT == address(0)) revert ZeroAddress();
        if (_userStateLedger == address(0)) revert ZeroAddress();
        if (_protocolAdmin == address(0)) revert ZeroAddress();

        registry = WorkflowRegistry(_registry);
        treasury = ProtocolTreasury(payable(_treasury));

        userStateINFT = _userStateINFT;
        userStateLedger = _userStateLedger;

        protocolAdmin = _protocolAdmin;
    }

    // -----------------------------------------------------

    struct StepInput {
        address agent;
        bytes32 inputType;
        bytes32 outputType;
    }

    struct CreateWorkflowParams {
        StepInput[] steps;
        string name;
        string description;
        address admin;
    }

    // -----------------------------------------------------

    function createWorkflow(
        CreateWorkflowParams calldata p
    ) external returns (address workflowAddr, uint256 workflowId) {
        if (p.steps.length == 0) revert EmptyWorkflow();

        IWorkflowInstance.StepSpec[] memory specs = _validateAndSnapshot(
            p.steps
        );

        uint256 totalCost;
        for (uint256 i = 0; i < specs.length; i++) {
            totalCost += specs[i].cost;
        }

        WorkflowInstance wf = new WorkflowInstance(
            WorkflowInstance.InitParams({
                factory: address(this),
                creator: msg.sender,
                admin: p.admin,
                inft: userStateINFT,
                treasury: address(treasury),
                ledger: userStateLedger, // ✅ NEW
                steps: specs,
                name: p.name,
                description: p.description
            })
        );

        workflowAddr = address(wf);

        treasury.registerWorkflow(workflowAddr);

        for (uint256 i = 0; i < specs.length; i++) {
            IAgent(specs[i].agent).joinWorkflow(workflowAddr);
        }

        workflowId = registry.registerWorkflow(
            IWorkflowRegistry.RegisterParams({
                workflowAddress: workflowAddr,
                creator: msg.sender,
                inputType: specs[0].inputType,
                outputType: specs[specs.length - 1].outputType,
                totalCost: totalCost,
                stepCount: specs.length,
                name: p.name,
                description: p.description
            })
        );

        creatorToWorkflows[msg.sender].push(workflowAddr);
        allWorkflows.push(workflowAddr);
    }

    // -----------------------------------------------------

    function _validateAndSnapshot(
        StepInput[] calldata steps
    ) internal view returns (IWorkflowInstance.StepSpec[] memory specs) {
        specs = new IWorkflowInstance.StepSpec[](steps.length);

        for (uint256 i = 0; i < steps.length; i++) {
            address a = steps[i].agent;
            if (a == address(0)) revert AgentZeroAddress(i);

            IAgent m = IAgent(a);

            if (!m.isWorkflowReady()) revert AgentNotWorkflowReady(i, a);
            if (m.isPaused()) revert AgentPaused(i, a);

            if (!m.supportsInput(steps[i].inputType)) {
                revert AgentDoesNotSupportInput(i, a, steps[i].inputType);
            }

            bytes32 out = m.getOutputType();
            if (out != steps[i].outputType) {
                revert TypeChainBroken(i, steps[i].outputType, out);
            }

            if (i > 0 && steps[i].inputType != steps[i - 1].outputType) {
                revert TypeChainBroken(
                    i,
                    steps[i - 1].outputType,
                    steps[i].inputType
                );
            }

            specs[i] = IWorkflowInstance.StepSpec({
                agent: a,
                inputType: steps[i].inputType,
                outputType: steps[i].outputType,
                cost: m.quote(),
                payoutAddress: m.payoutAddress()
            });
        }
    }

    // -----------------------------------------------------

    function quoteWorkflow(
        StepInput[] calldata steps
    ) external view returns (uint256[] memory costs, uint256 total) {
        if (steps.length == 0) revert EmptyWorkflow();

        IWorkflowInstance.StepSpec[] memory specs = _validateAndSnapshot(steps);

        costs = new uint256[](specs.length);

        for (uint256 i = 0; i < specs.length; i++) {
            costs[i] = specs[i].cost;
            total += specs[i].cost;
        }
    }
}
