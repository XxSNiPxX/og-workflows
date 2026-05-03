// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/WorkflowFactory.sol";
import "../src/WorkflowRegistry.sol";
import "../src/ProtocolTreasury.sol";
import "../src/UserStateINFT.sol";
import "../src/UserStateLedger.sol";
import "../src/WorkflowInstance.sol";
import "../src/AgentRegistry.sol";

import "../src/oracles/MockERC7857Oracle.sol";
import "../src/libraries/LibPermissionScope.sol";
import "./mocks/MockAgent.sol";

contract WorkflowInstanceTest is Test {
    WorkflowFactory factory;
    WorkflowRegistry registry;
    ProtocolTreasury treasury;
    UserStateINFT inft;
    UserStateLedger ledger;
    AgentRegistry agentRegistry;
    MockERC7857Oracle oracle;

    address admin = address(1);
    address user = address(2);

    address payoutA = address(30);
    address payoutB = address(31);

    function setUp() public {
        oracle = new MockERC7857Oracle(admin);
        inft = new UserStateINFT(admin, address(oracle));
        ledger = new UserStateLedger(address(inft));

        treasury = new ProtocolTreasury(admin, address(0), 0);
        registry = new WorkflowRegistry(admin);
        agentRegistry = new AgentRegistry(admin);

        factory = new WorkflowFactory(
            address(registry),
            address(treasury),
            address(agentRegistry), // ✅ NEW
            address(inft),
            address(ledger),
            admin
        );

        vm.prank(admin);
        registry.setFactory(address(factory));

        vm.prank(admin);
        treasury.setFactory(address(factory));

        vm.deal(user, 100 ether);
    }

    function _hash(string memory s) internal pure returns (bytes32) {
        return keccak256(bytes(s));
    }

    struct Setup {
        WorkflowInstance wf;
        address wfAddr;
        uint256 tokenId;
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

    function _fullyPrimed() internal returns (Setup memory s) {
        MockAgent a1 = new MockAgent(
            _hash("type:txt"),
            _hash("type:emb"),
            0.01 ether,
            payoutA
        );

        MockAgent a2 = new MockAgent(
            _hash("type:emb"),
            _hash("type:vec"),
            0.02 ether,
            payoutB
        );

        // ✅ REGISTER AGENTS
        _registerAgent(address(a1), _hash("type:txt"), _hash("type:emb"), 0.01 ether, payoutA);
        _registerAgent(address(a2), _hash("type:emb"), _hash("type:vec"), 0.02 ether, payoutB);

        WorkflowFactory.StepInput[] memory steps = new WorkflowFactory.StepInput[](2);

        steps[0] = WorkflowFactory.StepInput(address(a1), _hash("type:txt"), _hash("type:emb"));
        steps[1] = WorkflowFactory.StepInput(address(a2), _hash("type:emb"), _hash("type:vec"));

        vm.prank(user);
        (address wfAddr, ) = factory.createWorkflow(
            WorkflowFactory.CreateWorkflowParams({
                steps: steps,
                name: "wf",
                description: "test",
                admin: address(0)
            })
        );

        WorkflowInstance wf = WorkflowInstance(wfAddr);

        vm.prank(user);
        uint256 tokenId = inft.mint(user, bytes32(0), hex"01", "");

        LibPermissionScope.PermissionScope memory scope;
        scope.canRead = true;
        scope.canWrite = true;
        scope.canAppend = true;
        scope.allowedTypes = new bytes32[](0);
        scope.allowedWorkflowIds = new uint256[](0);

        vm.prank(user);
        inft.authorizeUsage(tokenId, wfAddr, LibPermissionScope.encode(scope));

        return Setup(wf, wfAddr, tokenId);
    }

    function testStartHappy() public {
        Setup memory s = _fullyPrimed();

        uint256 total = s.wf.totalCost();

        vm.prank(user);
        s.wf.start{value: total}(s.tokenId, _hash("input"));

        assertEq(treasury.balanceOf(s.wfAddr, 1), total);
    }

    function testCancelRefunds() public {
        Setup memory s = _fullyPrimed();

        uint256 total = s.wf.totalCost();

        vm.prank(user);
        s.wf.start{value: total}(s.tokenId, _hash("input"));

        vm.prank(user);
        s.wf.cancelRun(1);

        WorkflowInstance.Run memory r = s.wf.getRun(1);
        assertEq(uint256(r.status), 4); // CANCELLED
    }
}
