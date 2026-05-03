// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/ProtocolTreasury.sol";
import "../src/UserStateINFT.sol";
import "../src/UserStateLedger.sol";
import "../src/WorkflowFactory.sol";
import "../src/WorkflowInstance.sol";
import "../src/WorkflowRegistry.sol";
import "../src/oracles/MockERC7857Oracle.sol";
import "../src/libraries/LibPermissionScope.sol";
import "./mocks/MockAgent.sol";
import "../src/AgentRegistry.sol"; // ✅ ADD

contract CallbackMockAgent is MockAgent {
    constructor(
        bytes32 _in,
        bytes32 _out,
        uint256 _price,
        address _payout
    ) MockAgent(_in, _out, _price, _payout) {}

    function simulateComplete(
        bytes32 key,
        bytes32 outputPointer,
        bytes32 outputHash
    ) external {
        RequestRecord storage r = requests[key];
        require(r.createdAt != 0, "unknown key");

        r.outputPointer = outputPointer;
        r.outputType = outputType;
        r.outputHash = outputHash;
        r.status = RequestStatus.COMPLETED;
        r.updatedAt = uint64(block.timestamp);

        IWorkflowInstance(r.workflow).onStepCompleted(
            r.runId,
            r.stepIndex,
            outputPointer,
            outputType,
            outputHash
        );
    }
}

contract MegaIntegrationTest is Test {
    address admin = makeAddr("admin");
    address user1 = makeAddr("user1");
    address devAlice = makeAddr("alice");
    address devBob = makeAddr("bob");
    address feeRecipient = makeAddr("fee");

    MockERC7857Oracle oracle;
    UserStateINFT inft;
    UserStateLedger ledger;
    WorkflowRegistry registry;
    ProtocolTreasury treasury;
    WorkflowFactory factory;

    AgentRegistry agentRegistry; // ✅ ADD

    function setUp() public {
        oracle = new MockERC7857Oracle(admin);

        inft = new UserStateINFT(admin, address(oracle));
        ledger = new UserStateLedger(address(inft));

        registry = new WorkflowRegistry(admin);
        treasury = new ProtocolTreasury(admin, feeRecipient, 0);

        agentRegistry = new AgentRegistry(admin); // ✅ ADD

        factory = new WorkflowFactory(
            address(registry),
            address(treasury),
            address(agentRegistry), // ✅ NEW ARG
            address(inft),
            address(ledger),
            admin
        );

        vm.prank(admin);
        registry.setFactory(address(factory));

        vm.prank(admin);
        treasury.setFactory(address(factory));

        vm.deal(user1, 100 ether);
    }

    function H(string memory s) internal pure returns (bytes32) {
        return keccak256(bytes(s));
    }

    function _mintAndAuthorize(
        address user,
        address wfAddr
    ) internal returns (uint256 tokenId) {
        vm.prank(user);
        tokenId = inft.mint(
            user,
            keccak256(abi.encodePacked("identity", user)),
            hex"01",
            ""
        );

        LibPermissionScope.PermissionScope memory scope;
        scope.canRead = true;
        scope.canWrite = true;
        scope.canAppend = true;

        scope.allowedTypes = new bytes32[](0);
        scope.allowedWorkflowIds = new uint256[](1);
        scope.allowedWorkflowIds[0] = uint256(uint160(wfAddr));

        scope.expiresAt = 0;

        vm.prank(user);
        inft.authorizeUsage(tokenId, wfAddr, LibPermissionScope.encode(scope));
    }

    function _registerAgent(
        address agent,
        bytes32 inputType,
        bytes32 outputType,
        uint256 cost,
        address payout
    ) internal {
        bytes32[] memory inputs = new bytes32[](1);
        inputs[0] = inputType;

        vm.prank(admin);
        agentRegistry.setFactory(admin);

        vm.prank(admin);
        agentRegistry.registerAgent(
            IAgentRegistry.RegisterParams({
                agentAddress: agent,
                creator: admin,
                admin: admin,
                payoutAddress: payout,
                inputTypes: inputs,
                outputType: outputType,
                costPerRequest: cost,
                workflowReady: true,
                name: "agent",
                description: "",
                manifestHash: bytes32(0)
            })
        );
    }

    function _buildWorkflow()
        internal
        returns (
            address wfAddr,
            CallbackMockAgent a1,
            CallbackMockAgent a2,
            CallbackMockAgent a3
        )
    {
        a1 = new CallbackMockAgent(
            H("type:txt"),
            H("type:emb"),
            0.01 ether,
            devAlice
        );

        a2 = new CallbackMockAgent(
            H("type:emb"),
            H("type:vec"),
            0.02 ether,
            devAlice
        );

        a3 = new CallbackMockAgent(
            H("type:vec"),
            H("type:report"),
            0.03 ether,
            devBob
        );

        // ✅ CRITICAL FIX: REGISTER AGENTS
        _registerAgent(
            address(a1),
            H("type:txt"),
            H("type:emb"),
            0.01 ether,
            devAlice
        );
        _registerAgent(
            address(a2),
            H("type:emb"),
            H("type:vec"),
            0.02 ether,
            devAlice
        );
        _registerAgent(
            address(a3),
            H("type:vec"),
            H("type:report"),
            0.03 ether,
            devBob
        );

        WorkflowFactory.StepInput[]
            memory steps = new WorkflowFactory.StepInput[](3);

        steps[0] = WorkflowFactory.StepInput(
            address(a1),
            H("type:txt"),
            H("type:emb")
        );

        steps[1] = WorkflowFactory.StepInput(
            address(a2),
            H("type:emb"),
            H("type:vec")
        );

        steps[2] = WorkflowFactory.StepInput(
            address(a3),
            H("type:vec"),
            H("type:report")
        );

        vm.prank(user1);
        (wfAddr, ) = factory.createWorkflow(
            WorkflowFactory.CreateWorkflowParams({
                steps: steps,
                name: "pipeline",
                description: "dummy",
                admin: address(0)
            })
        );
    }

    function _key(
        WorkflowInstance wf,
        uint256 runId,
        uint256 stepIndex
    ) internal view returns (bytes32) {
        return wf.getRequestKey(runId, stepIndex);
    }

    function _complete(
        CallbackMockAgent agent,
        bytes32 key,
        string memory label
    ) internal {
        vm.prank(address(agent));
        agent.simulateComplete(
            key,
            H(label),
            keccak256(abi.encodePacked(label))
        );
    }

    function testFullWorkflowFlowPaysAndWritesLedger() public {
        (
            address wfAddr,
            CallbackMockAgent a1,
            CallbackMockAgent a2,
            CallbackMockAgent a3
        ) = _buildWorkflow();

        WorkflowInstance wf = WorkflowInstance(wfAddr);
        uint256 tokenId = _mintAndAuthorize(user1, wfAddr);

        vm.prank(user1);
        wf.start{value: wf.totalCost()}(tokenId, H("input"));

        _complete(a1, _key(wf, 1, 0), "emb");
        assertEq(ledger.totalItems(tokenId), 1);

        _complete(a2, _key(wf, 1, 1), "vec");
        assertEq(ledger.totalItems(tokenId), 2);

        _complete(a3, _key(wf, 1, 2), "report");

        assertEq(ledger.totalItems(tokenId), 3);
        assertEq(uint256(wf.getRun(1).status), 2);
    }

    function testUnderpaymentReverts() public {
        (address wfAddr, , , ) = _buildWorkflow();
        WorkflowInstance wf = WorkflowInstance(wfAddr);

        uint256 tokenId = _mintAndAuthorize(user1, wfAddr);

        vm.prank(user1);
        vm.expectRevert(WorkflowInstance.InsufficientPayment.selector);
        wf.start{value: 0.01 ether}(tokenId, H("input"));
    }

    function testCancelRefundsRemaining() public {
        (address wfAddr, CallbackMockAgent a1, , ) = _buildWorkflow();
        WorkflowInstance wf = WorkflowInstance(wfAddr);

        uint256 tokenId = _mintAndAuthorize(user1, wfAddr);

        vm.prank(user1);
        wf.start{value: wf.totalCost()}(tokenId, H("input"));

        _complete(a1, _key(wf, 1, 0), "emb");

        vm.prank(user1);
        wf.cancelRun(1);

        assertEq(uint256(wf.getRun(1).status), 4);
        assertEq(ledger.totalItems(tokenId), 1);
    }
}
