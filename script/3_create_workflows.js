const { ethers } = require("ethers");
const fs = require("fs");

// ---------------- CONFIG ----------------

const wallets = JSON.parse(fs.readFileSync("./deployments/wallets.json"));
const deployedPath = "../deployments/galileo.json";
const deployed = JSON.parse(fs.readFileSync(deployedPath));

if (!deployed.workflowFactory) throw new Error("workflowFactory missing");
if (!deployed.agents) throw new Error("agents missing");

// ---------------- PROVIDER ----------------

const provider = new ethers.JsonRpcProvider(wallets.rpc);
const signer = new ethers.Wallet(wallets.users[0].privateKey, provider);

// ---------------- CONTRACT ----------------

const artifact = require("/home/snip/Projects/web3/hello_foundry/out/WorkflowFactory.sol/WorkflowFactory.json");

const factory = new ethers.Contract(
  deployed.workflowFactory,
  artifact.abi,
  signer,
);

// ---------------- EVENT PARSER ----------------

const iface = new ethers.Interface(artifact.abi);

function extractWorkflow(receipt) {
  for (const log of receipt.logs) {
    try {
      const parsed = iface.parseLog(log);

      if (parsed.name === "WorkflowCreated") {
        return parsed.args.workflow;
      }
    } catch {}
  }
  return null;
}

// ---------------- AGENT ABI ----------------

const agentAbi = [
  "function getInputTypes() view returns (bytes32[])",
  "function getOutputType() view returns (bytes32)",
  "function supportsInput(bytes32) view returns (bool)",
  "function isPaused() view returns (bool)",
];

// ---------------- UTILS ----------------

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function waitForReceipt(hash, tries = 30) {
  for (let i = 0; i < tries; i++) {
    const receipt = await provider.getTransactionReceipt(hash);
    if (receipt) return receipt;
    await sleep(2000);
  }
  return null;
}

// ---------------- BUILD PIPELINE ----------------

async function buildSteps() {
  const agents = deployed.agents
    .filter((a) => a && a.diamond)
    .map((a) => a.diamond);

  if (agents.length === 0) throw new Error("No valid agents");

  const steps = [];
  let prevOutput = null;

  for (let i = 0; i < agents.length; i++) {
    const addr = agents[i];
    const agent = new ethers.Contract(addr, agentAbi, provider);

    const inputs = await agent.getInputTypes();
    const output = await agent.getOutputType();
    const paused = await agent.isPaused();

    console.log("\nAgent:", addr);
    console.log("Inputs:", inputs);
    console.log("Output:", output);

    if (paused) throw new Error(`Agent paused: ${addr}`);
    if (inputs.length === 0) throw new Error(`No inputs: ${addr}`);

    let chosenInput;

    if (i === 0) {
      chosenInput = inputs[0];
    } else {
      const match = inputs.find((x) => x === prevOutput);
      if (!match) {
        console.log("⚠ chain break → stopping pipeline");
        break;
      }
      chosenInput = match;
    }

    const supports = await agent.supportsInput(chosenInput);
    if (!supports) throw new Error(`supportsInput false: ${addr}`);

    steps.push({
      agent: addr,
      inputType: chosenInput,
      outputType: output,
    });

    prevOutput = output;
  }

  if (steps.length === 0) throw new Error("No valid pipeline");

  return steps;
}

// ---------------- CREATE WORKFLOW ----------------

async function createWorkflow() {
  const steps = await buildSteps();

  console.log("\n--- FINAL STEPS ---");
  console.log(steps);

  // -------- STATIC --------

  await factory.createWorkflow.staticCall(
    steps,
    "pipeline",
    "auto",
    signer.address,
  );

  console.log("✓ Static OK");

  // -------- GAS + NONCE --------

  const fee = await provider.getFeeData();
  const nonce = await provider.getTransactionCount(signer.address, "latest");

  // -------- SEND --------

  const tx = await factory.createWorkflow(
    steps,
    "pipeline",
    "auto",
    signer.address,
    {
      gasLimit: 3_000_000,
      maxFeePerGas: fee.maxFeePerGas,
      maxPriorityFeePerGas: fee.maxPriorityFeePerGas,
      nonce,
    },
  );

  console.log("TX SENT →", tx.hash);

  // -------- VERIFY BROADCAST --------

  await sleep(2000);

  const seen = await provider.getTransaction(tx.hash);
  if (!seen) throw new Error("TX NOT BROADCAST");

  console.log("✓ Broadcast visible");

  // -------- WAIT --------

  const receipt = await waitForReceipt(tx.hash);

  if (!receipt) {
    console.log("⚠ NOT INCLUDED");
    return null;
  }

  if (receipt.status === 0) {
    throw new Error("TX FAILED");
  }

  console.log("✓ INCLUDED → block", receipt.blockNumber);

  // -------- EXTRACT WORKFLOW --------

  const workflow = extractWorkflow(receipt);

  if (!workflow) {
    throw new Error("WorkflowCreated event not found");
  }

  console.log("✓ WORKFLOW →", workflow);

  return workflow;
}

// ---------------- MAIN ----------------

async function main() {
  console.log("Signer:", signer.address);
  console.log("WorkflowFactory:", deployed.workflowFactory);

  const code = await provider.getCode(deployed.workflowFactory);
  if (code === "0x") throw new Error("Factory not deployed");

  console.log("✓ Factory code exists");

  const block = await provider.getBlockNumber();
  console.log("Current block:", block);

  const workflow = await createWorkflow();

  if (!workflow) return;

  // -------- SAVE --------

  deployed.workflows = deployed.workflows || [];
  deployed.workflows.push(workflow);

  fs.writeFileSync(deployedPath, JSON.stringify(deployed, null, 2));

  console.log("✓ Saved workflow →", deployedPath);

  console.log("\nDONE");
}

main().catch((e) => {
  console.error("FATAL:", e.message || e);
  process.exit(1);
});
