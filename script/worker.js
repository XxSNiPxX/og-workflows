const { ethers } = require("ethers");
const fs = require("fs");

// ---------------- CONFIG ----------------

const wallets = JSON.parse(fs.readFileSync("./deployments/wallets.json"));

const provider = new ethers.JsonRpcProvider(wallets.rpc);
const signer = new ethers.Wallet(wallets.agents[0].privateKey, provider);

console.log("Worker:", signer.address);

// 🔴 LOAD REAL AGENTS FROM FILE
const agentsJson = JSON.parse(
  fs.readFileSync("../deployments/agents_new.json"),
);

const AGENTS = Object.entries(agentsJson.agents)
  .filter(([k]) => k.endsWith("_diamond"))
  .map(([, v]) => v.toLowerCase());

console.log("Watching agents:", AGENTS);

// ---------------- ABI ----------------

const agentAbi = [
  "function complete(bytes32,bytes32,bytes32,bytes32,bytes32,uint8)",
  "function getOutputType() view returns (bytes32)",
  "function getPendingRequests() view returns (bytes32[])",
];

// ---------------- STATE ----------------

let nonce;
const seen = new Set();

// ---------------- UTILS ----------------

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------- NONCE ----------------

async function initNonce() {
  nonce = await provider.getTransactionCount(signer.address, "pending");
  console.log("Starting nonce:", nonce);
}

// ---------------- EXECUTE ----------------

async function execute(agentAddr, key) {
  const id = `${agentAddr}-${key}`;
  if (seen.has(id)) return;
  seen.add(id);

  try {
    const agent = new ethers.Contract(agentAddr, agentAbi, signer);

    const outputPointer = ethers.keccak256(
      ethers.toUtf8Bytes(`${Date.now()}-${key}`),
    );

    const outputHash = ethers.keccak256(
      ethers.toUtf8Bytes(`result-${key}-${Date.now()}`),
    );

    const outputType = await agent.getOutputType();

    console.log("\nEXEC:", { agent: agentAddr, key });

    const tx = await agent.complete(
      key,
      outputPointer,
      outputType,
      outputHash,
      ethers.ZeroHash,
      0,
      {
        nonce,
        gasLimit: 800000,
      },
    );

    console.log("TX:", tx.hash, "| nonce:", nonce);
    nonce++;

    const receipt = await tx.wait();

    console.log("RECEIPT:", {
      status: receipt.status,
      block: receipt.blockNumber,
    });

    if (receipt.status !== 1) {
      console.log("✗ FAILED");
      seen.delete(id);
    } else {
      console.log("✓ DONE");
    }
  } catch (e) {
    console.log("EXEC ERROR:", e.shortMessage || e.message);

    nonce = await provider.getTransactionCount(signer.address, "pending");
    console.log("Resynced nonce:", nonce);

    seen.delete(id);
  }
}

// ---------------- POLL ----------------

async function pollPending() {
  for (const agentAddr of AGENTS) {
    try {
      const agent = new ethers.Contract(agentAddr, agentAbi, provider);

      let pending;

      try {
        pending = await agent.getPendingRequests();
      } catch (err) {
        console.log("BAD AGENT:", agentAddr);
        continue;
      }

      if (pending.length > 0) {
        console.log(`\nPENDING @ ${agentAddr}:`, pending.length);
      }

      for (const key of pending) {
        await execute(agentAddr, key);
      }
    } catch (e) {
      console.log("POLL ERROR:", agentAddr, e.message);
    }
  }
}

// ---------------- MAIN ----------------

async function main() {
  await initNonce();

  while (true) {
    await pollPending();
    await sleep(1500);
  }
}

main();
