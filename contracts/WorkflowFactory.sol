// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {WorkflowInstance} from "./WorkflowInstance.sol";
import {WorkflowRegistry} from "./WorkflowRegistry.sol";
import {ProtocolTreasury} from "./ProtocolTreasury.sol";
import {IWorkflowInstance} from "./interfaces/IWorkflowInstance.sol";
import {IWorkflowRegistry} from "./interfaces/IWorkflowRegistry.sol";
import {IAgentManifest} from "./interfaces/IAgentManifest.sol";
import {IAgentPermission} from "./interfaces/IAgentPermission.sol";

/// @title WorkflowFactory
/// @notice Single entry point for creating workflows.
///
///         createWorkflow(...) does, atomically:
///           1. Validate the step chain — each step's inputType must match
///              the previous step's outputType.
///           2. For every agent in the chain:
///              - check workflowReady = true
///              - check supportsInput(step.inputType) = true
///              - snapshot quote() and the manifest's payoutAddress
///           3. Sum up totalCost.
///           4. Deploy a WorkflowInstance carrying that frozen snapshot.
///           5. Register the workflow with the treasury (so it can deposit /
///              release / refund escrows).
///           6. For every agent: call agent.joinWorkflow(workflowAddr) — this
///              adds the workflow as a trustedCaller on the agent's permission
///              facet (only succeeds if the agent has a registered factory and
///              workflowReady is true; both already validated above).
///           7. Register the workflow in the WorkflowRegistry.
contract WorkflowFactory {
    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    WorkflowRegistry public immutable registry;
    ProtocolTreasury public immutable treasury;
    address public immutable userStateINFT;
    address public protocolAdmin;

    mapping(address => address[]) public creatorToWorkflows;
    address[] public allWorkflows;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event WorkflowCreated(
        uint256 indexed workflowId,
        address indexed workflow,
        address indexed creator
    );
    event ProtocolAdminSet(address admin);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error NotProtocolAdmin();
    error ZeroAddress();
    error EmptyWorkflow();
    error AgentZeroAddress(uint256 stepIndex);
    error AgentNotWorkflowReady(uint256 stepIndex, address agent);
    error AgentDoesNotSupportInput(uint256 stepIndex, address agent, bytes32 inputType);
    error TypeChainBroken(uint256 stepIndex, bytes32 expected, bytes32 got);
    error AgentPaused(uint256 stepIndex, address agent);

    // ---------------------------------------------------------------------
    // Init
    // ---------------------------------------------------------------------

    constructor(
        address _registry,
        address _treasury,
        address _userStateINFT,
        address _protocolAdmin
    ) {
        if (_registry == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();
        if (_userStateINFT == address(0)) revert ZeroAddress();
        if (_protocolAdmin == address(0)) revert ZeroAddress();
        registry = WorkflowRegistry(_registry);
        treasury = ProtocolTreasury(payable(_treasury));
        userStateINFT = _userStateINFT;
        protocolAdmin = _protocolAdmin;
        emit ProtocolAdminSet(_protocolAdmin);
    }

    modifier onlyProtocolAdmin() {
        if (msg.sender != protocolAdmin) revert NotProtocolAdmin();
        _;
    }

    function setProtocolAdmin(address _admin) external onlyProtocolAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        protocolAdmin = _admin;
        emit ProtocolAdminSet(_admin);
    }

    // ---------------------------------------------------------------------
    // createWorkflow
    // ---------------------------------------------------------------------

    /// @notice Step inputs from the user: which agents to chain, plus the
    ///         expected I/O types per step. Costs and payouts are NOT supplied
    ///         here — they're snapshotted from the agent manifests.
    struct StepInput {
        address agent;
        bytes32 inputType;
        bytes32 outputType;
    }

    struct CreateWorkflowParams {
        StepInput[] steps;
        string name;
        string description;
        address admin; // workflow admin (defaults to creator if zero)
    }

    function createWorkflow(CreateWorkflowParams calldata p)
        external
        returns (address workflowAddr, uint256 workflowId)
    {
        if (p.steps.length == 0) revert EmptyWorkflow();

        // 1. Validate type chain + snapshot per-step cost & payout.
        IWorkflowInstance.StepSpec[] memory specs = _validateAndSnapshot(p.steps);

        // 2. Sum costs (already done in _validateAndSnapshot but we recompute
        //    to keep _validateAndSnapshot's return tight).
        uint256 totalCost;
        for (uint256 i = 0; i < specs.length; i++) {
            totalCost += specs[i].cost;
        }

        // 3. Deploy WorkflowInstance.
        WorkflowInstance.InitParams memory ip = WorkflowInstance.InitParams({
            factory: address(this),
            creator: msg.sender,
            admin: p.admin,
            inft: userStateINFT,
            treasury: address(treasury),
            steps: specs,
            name: p.name,
            description: p.description
        });
        WorkflowInstance wf = new WorkflowInstance(ip);
        workflowAddr = address(wf);

        // 4. Register with treasury so workflow can call deposit/release/refund.
        treasury.registerWorkflow(workflowAddr);

        // 5. Wire as trustedCaller on every agent in the chain. Each agent
        //    permission facet's joinWorkflow() validates workflowReady=true
        //    again as a defence-in-depth check.
        for (uint256 i = 0; i < specs.length; i++) {
            IAgentPermission(specs[i].agent).joinWorkflow(workflowAddr);
        }

        // 6. Register in global workflow registry.
        workflowId = registry.registerWorkflow(IWorkflowRegistry.RegisterParams({
            workflowAddress: workflowAddr,
            creator: msg.sender,
            inputType: specs[0].inputType,
            outputType: specs[specs.length - 1].outputType,
            totalCost: totalCost,
            stepCount: specs.length,
            name: p.name,
            description: p.description
        }));

        // 7. Local bookkeeping
        creatorToWorkflows[msg.sender].push(workflowAddr);
        allWorkflows.push(workflowAddr);

        emit WorkflowCreated(workflowId, workflowAddr, msg.sender);
    }

    // ---------------------------------------------------------------------
    // Internal: validate + snapshot
    // ---------------------------------------------------------------------

    function _validateAndSnapshot(StepInput[] calldata steps)
        internal
        view
        returns (IWorkflowInstance.StepSpec[] memory specs)
    {
        specs = new IWorkflowInstance.StepSpec[](steps.length);

        for (uint256 i = 0; i < steps.length; i++) {
            address a = steps[i].agent;
            if (a == address(0)) revert AgentZeroAddress(i);

            IAgentManifest m = IAgentManifest(a);

            if (!m.isWorkflowReady()) revert AgentNotWorkflowReady(i, a);
            if (m.isPaused()) revert AgentPaused(i, a);
            if (!m.supportsInput(steps[i].inputType)) {
                revert AgentDoesNotSupportInput(i, a, steps[i].inputType);
            }
            // The agent's actual outputType must match what the workflow caller
            // claims it will produce (and what the next step expects as input).
            bytes32 actualOut = m.getOutputType();
            if (actualOut != steps[i].outputType) {
                revert TypeChainBroken(i, steps[i].outputType, actualOut);
            }

            // Type-chain link: this step's input must equal previous step's output.
            if (i > 0 && steps[i].inputType != steps[i - 1].outputType) {
                revert TypeChainBroken(i, steps[i - 1].outputType, steps[i].inputType);
            }

            specs[i] = IWorkflowInstance.StepSpec({
                agent: a,
                inputType: steps[i].inputType,
                outputType: steps[i].outputType,
                cost: m.quote(),
                payoutAddress: _readPayout(a)
            });
        }
    }

    /// @dev    The agent's manifest exposes payoutAddress only via the full
    ///         getManifest() struct. We do a low-level call for it because
    ///         IAgentManifest doesn't expose payoutAddress directly (there's
    ///         no point bloating the interface with a field already in the
    ///         struct).
    function _readPayout(address agent) internal view returns (address) {
        (bool ok, bytes memory data) = agent.staticcall(
            abi.encodeWithSignature("getManifest()")
        );
        require(ok && data.length > 0, "WF: getManifest failed");

        // Decode minimally — we only need the payoutAddress field. The
        // manifest struct layout is:
        //   string, string, bytes32, bytes32[], bytes32, uint256, address payoutAddress, ...
        // Decoding the full struct would also work (and uses the canonical
        // ABI for struct returns), so do that:
        // Note: this decoding mirrors AgentRegistry.syncAgent which uses the
        // full struct decode pattern.
        ManifestSlim memory ms = abi.decode(data, (ManifestSlim));
        return ms.payoutAddress;
    }

    /// @dev    Mirrors LibAgentManifestStorage.AgentManifest field-for-field.
    ///         Kept private to this contract so the manifest library doesn't
    ///         leak through the WorkflowFactory's public interface.
    struct ManifestSlim {
        string name;
        string description;
        bytes32 manifestHash;
        bytes32[] inputTypes;
        bytes32 outputType;
        uint256 costPerRequest;
        address payoutAddress;
        bool workflowReady;
        bool paused;
        uint64 createdAt;
        uint64 updatedAt;
    }

    // ---------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------

    function getWorkflowsByCreator(address dev) external view returns (address[] memory) {
        return creatorToWorkflows[dev];
    }

    function getAllWorkflows() external view returns (address[] memory) {
        return allWorkflows;
    }

    function totalWorkflows() external view returns (uint256) {
        return allWorkflows.length;
    }

    /// @notice Off-chain quote: validates the chain and returns the snapshot
    ///         per-step costs + totalCost without deploying anything.
    /// @dev    Reverts on the same conditions as createWorkflow, so callers
    ///         can use this to surface validation errors before paying gas
    ///         for deployment.
    function quoteWorkflow(StepInput[] calldata steps)
        external
        view
        returns (uint256[] memory perStepCost, uint256 totalCost)
    {
        if (steps.length == 0) revert EmptyWorkflow();
        IWorkflowInstance.StepSpec[] memory specs = _validateAndSnapshot(steps);
        perStepCost = new uint256[](specs.length);
        for (uint256 i = 0; i < specs.length; i++) {
            perStepCost[i] = specs[i].cost;
            totalCost += specs[i].cost;
        }
    }
}
