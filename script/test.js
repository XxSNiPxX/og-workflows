const { ethers } = require("ethers");
const fs = require("fs");

// ---------------- CONFIG ----------------

// 🔴 update paths if needed
const DEPLOY_PATH = "../deployments/galileo.json";
const AGENTS_PATH = "../deployments/agents_new.json";
const WORKFLOWS_PATH = "../deployments/workflows_new.json";
const WALLETS_PATH = "./deployments/wallets.json";

// ---------------- LOAD JSON ----------------

function loadJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

const wallets = loadJson(WALLETS_PATH);
const deploy = loadJson(DEPLOY_PATH);
const agentsJson = loadJson(AGENTS_PATH);
const workflowsJson = loadJson(WORKFLOWS_PATH);

// ---------------- PROVIDER ----------------

const provider = new ethers.JsonRpcProvider(wallets.rpc);

// ---------------- VALIDATION ----------------

function mustAddress(addr, label) {
  if (!addr || !ethers.isAddress(addr)) {
    throw new Error(`Invalid address for ${label}: ${addr}`);
  }
  return addr.toLowerCase();
}

// ---------------- EXTRACT ADDRESSES ----------------

// user
const USER = mustAddress(wallets.users[0].address, "USER");

// agent registry
const AGENT_REGISTRY = mustAddress(deploy.agentRegistry, "AGENT_REGISTRY");

// workflows
const WORKFLOWS = [mustAddress(workflowsJson.address, "WORKFLOW")];

// agents (dynamic from file)
const AGENTS = Object.entries(agentsJson.agents)
  .filter(([k]) => k.endsWith("_diamond"))
  .map(([, v]) => mustAddress(v, "AGENT"));

console.log("\nUSER:", USER);
console.log("WORKFLOWS:", WORKFLOWS);
console.log("AGENTS:", AGENTS);
console.log("REGISTRY:", AGENT_REGISTRY);

// ---------------- ABIs ----------------

const workflowAbi = [
  "function getUserRuns(address) view returns (uint256[])",
  "function getRun(uint256) view returns (tuple(address user,uint256 tokenId,uint256 currentStepIndex,bytes32 currentInputPointer,bytes32 currentInputType,uint8 status))",
  "function getStepKey(uint256,uint256) view returns (bytes32)",
];

const agentRegistryAbi = [
  "function getAllAgents() view returns (tuple(uint256 agentId,address agentAddress,address creator,address admin,address payoutAddress,bytes32[] inputTypes,bytes32 outputType,uint256 costPerRequest,bool workflowReady,bool active,uint64 createdAt,uint64 updatedAt,string name,string description,bytes32 manifestHash)[])",
];

const agentAbi = [
  "function getRequest(bytes32) view returns (tuple(address user,uint256 tokenId,uint256 runId,uint256 stepIndex,bytes32 inputPointer,bytes32 outputPointer,bytes32 outputType,bytes32 outputHash,uint8 status))",
];

// ---------------- HELPERS ----------------

function safeContract(addr, abi) {
  try {
    return new ethers.Contract(addr, abi, provider);
  } catch (e) {
    console.log("BAD CONTRACT:", addr);
    return null;
  }
}

// ---------------- AGENTS ----------------

async function getAllAgents() {
  console.log("\n=== AGENTS ===");

  const registry = safeContract(AGENT_REGISTRY, agentRegistryAbi);
  if (!registry) return;

  try {
    const agents = await registry.getAllAgents();

    for (const a of agents) {
      console.log({
        id: a.agentId.toString(),
        address: a.agentAddress,
        price: ethers.formatEther(a.costPerRequest),
        name: a.name,
        active: a.active,
      });
    }
  } catch (e) {
    console.log("AGENT FETCH ERROR:", e.shortMessage || e.message);
  }
}

// ---------------- RUNS ----------------

async function getRuns(workflowAddr) {
  console.log(`\n=== RUNS @ ${workflowAddr} ===`);

  const wf = safeContract(workflowAddr, workflowAbi);
  if (!wf) return;

  let runIds;

  try {
    runIds = await wf.getUserRuns(USER);
  } catch (e) {
    console.log("RUN FETCH ERROR:", e.shortMessage || e.message);
    return;
  }

  if (runIds.length === 0) {
    console.log("No runs.");
    return;
  }

  for (const runId of runIds) {
    try {
      const run = await wf.getRun(runId);

      console.log("\nRUN:", runId.toString(), {
        step: run.currentStepIndex.toString(),
        status: run.status,
        pointer: run.currentInputPointer,
      });

      const steps = Number(run.currentStepIndex) + 1;

      for (let i = 0; i < steps; i++) {
        try {
          const key = await wf.getStepKey(runId, i);
          console.log(`  step ${i} key:`, key);
        } catch {
          break;
        }
      }
    } catch (e) {
      console.log("RUN ERROR:", e.shortMessage || e.message);
    }
  }
}

// ---------------- OPTIONAL: AGENT DATA ----------------

async function inspectAgent(agentAddr, keys) {
  const agent = safeContract(agentAddr, agentAbi);
  if (!agent) return;

  for (const key of keys) {
    try {
      const r = await agent.getRequest(key);
      console.log("REQUEST:", {
        runId: r.runId.toString(),
        step: r.stepIndex.toString(),
        output: r.outputPointer,
      });
    } catch {}
  }
}

// ---------------- MAIN ----------------

async function main() {
  await getAllAgents();

  for (const wf of WORKFLOWS) {
    await getRuns(wf);
  }
}

main();
