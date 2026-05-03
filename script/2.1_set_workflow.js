const { ethers } = require("ethers");
const fs = require("fs");

// ---------------- CONFIG ----------------

const wallets = JSON.parse(fs.readFileSync("./deployments/wallets.json"));
const deployed = JSON.parse(fs.readFileSync("../deployments/galileo.json"));
const agentsNew = JSON.parse(fs.readFileSync("../deployments/agents_new.json"));

if (!deployed.workflowFactory) {
  throw new Error("workflowFactory missing");
}

if (!agentsNew.agents) {
  throw new Error("agents_new.json missing agents");
}

// ---------------- PROVIDER ----------------

const provider = new ethers.JsonRpcProvider(wallets.rpc);
const signer = new ethers.Wallet(wallets.agents[0].privateKey, provider);

// ---------------- ABI ----------------

const permAbi = [
  "function setWorkflowFactory(address)",
  "function getWorkflowFactory() view returns (address)",
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

// ---------------- LOAD AGENTS ----------------

function loadAgents() {
  const agents = [];

  for (let i = 0; i < 50; i++) {
    const addr = agentsNew.agents[`${i}_diamond`];

    if (!addr) break;

    agents.push(addr);
  }

  if (agents.length === 0) {
    throw new Error("no agents found in agents_new.json");
  }

  return agents;
}

// ---------------- CORE ----------------

async function setForAgent(addr) {
  const agent = new ethers.Contract(addr, permAbi, signer);

  console.log("\nAgent:", addr);

  const current = await agent.getWorkflowFactory();
  console.log("Current:", current);

  if (current.toLowerCase() === deployed.workflowFactory.toLowerCase()) {
    console.log("✓ already set");
    return;
  }

  const fee = await provider.getFeeData();
  const nonce = await provider.getTransactionCount(signer.address, "latest");

  const tx = await agent.setWorkflowFactory(deployed.workflowFactory, {
    maxFeePerGas: fee.maxFeePerGas,
    maxPriorityFeePerGas: fee.maxPriorityFeePerGas,
    gasLimit: 500_000,
    nonce,
  });

  console.log("TX SENT →", tx.hash);

  await sleep(2000);

  const seen = await provider.getTransaction(tx.hash);
  if (!seen) {
    throw new Error("TX NOT BROADCAST");
  }

  console.log("✓ Broadcast visible");

  const receipt = await waitForReceipt(tx.hash);

  if (!receipt) {
    console.log("⚠ NOT INCLUDED");
    return;
  }

  if (receipt.status === 0) {
    throw new Error("TX FAILED");
  }

  console.log("✓ INCLUDED → block", receipt.blockNumber);
}

// ---------------- MAIN ----------------

async function main() {
  const agents = loadAgents();

  console.log("Signer:", signer.address);
  console.log("WorkflowFactory:", deployed.workflowFactory);
  console.log("Agents loaded:", agents.length);

  for (const addr of agents) {
    await setForAgent(addr);
  }

  console.log("\nDONE");
}

main().catch((e) => {
  console.error("FATAL:", e.message || e);
  process.exit(1);
});
