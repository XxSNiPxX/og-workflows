// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {WorkflowInstance} from "./WorkflowInstance.sol";
import {IAgentPermission} from "./interfaces/IAgentPermission.sol";
import {IProtocolTreasury} from "./interfaces/IProtocolTreasury.sol";

interface IAgentView {
    function supportsInput(bytes32) external view returns (bool);

    function isPaused() external view returns (bool);

    function payoutAddress() external view returns (address);

    function quote() external view returns (uint256);
}

contract WorkflowFactory {
    struct Step {
        address agent;
        bytes32 inputType;
        bytes32 outputType;
    }

    event WorkflowCreated(address indexed workflow, address indexed creator);

    address public immutable treasury;

    // ✅ NEW
    mapping(address => address[]) public userWorkflows;

    constructor(address _treasury) {
        require(_treasury != address(0), "bad treasury");
        treasury = _treasury;
    }

    function createWorkflow(
        Step[] calldata steps,
        string calldata,
        string calldata,
        address
    ) external returns (address workflow) {
        require(steps.length > 0, "NO_STEPS");

        WorkflowInstance.StepSpec[]
            memory specs = new WorkflowInstance.StepSpec[](steps.length);

        bytes32 prevOutput;

        for (uint256 i = 0; i < steps.length; i++) {
            Step calldata s = steps[i];

            require(s.agent != address(0), "ZERO_AGENT");
            require(!IAgentView(s.agent).isPaused(), "PAUSED");
            require(
                IAgentView(s.agent).supportsInput(s.inputType),
                "BAD_INPUT"
            );

            if (i > 0) {
                require(s.inputType == prevOutput, "CHAIN_BREAK");
            }

            specs[i] = WorkflowInstance.StepSpec({
                agent: s.agent,
                cost: IAgentView(s.agent).quote(),
                payoutAddress: IAgentView(s.agent).payoutAddress(),
                inputType: s.inputType,
                outputType: s.outputType
            });

            prevOutput = s.outputType;
        }

        workflow = address(new WorkflowInstance(treasury, specs));

        // ✅ track creator workflows
        userWorkflows[msg.sender].push(workflow);

        IProtocolTreasury(treasury).registerWorkflow(workflow);

        for (uint256 i = 0; i < steps.length; i++) {
            IAgentPermission(steps[i].agent).joinWorkflow(workflow);
        }

        emit WorkflowCreated(workflow, msg.sender);
    }

    // ✅ getter
    function getUserWorkflows(
        address user
    ) external view returns (address[] memory) {
        return userWorkflows[user];
    }
}
