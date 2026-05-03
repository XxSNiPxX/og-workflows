const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

// ---------------- CONFIG ----------------

const wallets = JSON.parse(fs.readFileSync("./deployments/wallets.json"));

const provider = new ethers.JsonRpcProvider(wallets.rpc);
const signer = new ethers.Wallet(wallets.agents[0].privateKey, provider);

console.log("Worker:", signer.address);

// 🔴 AGENTS
const agentsJson = JSON.parse(
  fs.readFileSync("../deployments/agents_new.json"),
);

const AGENTS = Object.entries(agentsJson.agents)
  .filter(([k]) => k.endsWith("_diamond"))
  .map(([, v]) => v.toLowerCase());

console.log("Watching agents:", AGENTS);

// 🔴 KV + LOCAL STORE
const KV_RPC = "http://178.238.236.119:6789";
const STREAM_ID =
  "0x35dd3e73dd3d8474f286fb6f5af5a1e953662d2d5d176994520390e14bad083d";

const STORE_PATH = path.resolve(process.cwd(), "tmp-og-store.json");

// ---------------- ABI ----------------

const agentAbi = [
  "function complete(bytes32,bytes32,bytes32,bytes32,bytes32,uint8)",
  "function getOutputType() view returns (bytes32)",
  "function getPendingRequests() view returns (bytes32[])",
];

// ---------------- STATE ----------------

let nonce;
const seen = new Set();

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------- STORAGE ----------------

async function kv_get(pointer) {
  try {
    const res = await fetch(KV_RPC, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "kv_get",
        params: [STREAM_ID, pointer],
      }),
    });

    const json = await res.json();
    return json.result;
  } catch {
    return null;
  }
}

function local_get(pointer) {
  if (!fs.existsSync(STORE_PATH)) return null;

  try {
    const store = JSON.parse(fs.readFileSync(STORE_PATH, "utf-8"));
    return store[pointer] || null;
  } catch {
    return null;
  }
}

function local_put(pointer, data) {
  let store = {};

  if (fs.existsSync(STORE_PATH)) {
    try {
      store = JSON.parse(fs.readFileSync(STORE_PATH, "utf-8"));
    } catch {}
  }

  store[pointer] = data;

  fs.writeFileSync(STORE_PATH, JSON.stringify(store, null, 2));
}

// 🔴 unified loader
async function loadData(pointer) {
  // try KV first
  const kv = await kv_get(pointer);
  if (kv) {
    console.log("[LOAD] KV hit");
    return kv;
  }

  // fallback
  const local = local_get(pointer);
  if (local) {
    console.log("[LOAD] LOCAL fallback hit");
    return local;
  }

  throw new Error("No data found anywhere");
}

// ---------------- NONCE ----------------

async function initNonce() {
  nonce = await provider.getTransactionCount(signer.address, "pending");
  console.log("Starting nonce:", nonce);
}

// ---------------- LOGIC ----------------

function fakeWalletData(wallet) {
  const seed = parseInt(wallet.slice(2, 10), 16);

  return {
    wallet,
    coins: [
      { name: "DOGE", balance: (seed % 1000) + 100 },
      { name: "PEPE", balance: (seed % 500) + 50 },
    ],
  };
}

// ---------------- EXECUTE ----------------

async function execute(agentAddr, key) {
  const id = `${agentAddr}-${key}`;
  if (seen.has(id)) return;
  seen.add(id);

  try {
    const agent = new ethers.Contract(agentAddr, agentAbi, signer);

    const inputPointer = key;

    console.log("\nEXEC:", { agent: agentAddr, inputPointer });

    // 🔴 LOAD DATA (KV → FILE)
    const raw = await loadData(inputPointer);

    let outputData;

    try {
      const parsed = JSON.parse(raw);

      // Agent 2 → report
      outputData = `
Wallet Report

Wallet: ${parsed.wallet}

Holdings:
${parsed.coins.map((c) => `- ${c.name}: ${c.balance}`).join("\n")}
`;
    } catch {
      // Agent 1 → generate data
      outputData = JSON.stringify(fakeWalletData(raw));
    }

    // 🔴 STORE OUTPUT (ALWAYS LOCAL SAFE)
    const outputPointer = ethers.keccak256(ethers.toUtf8Bytes(outputData));

    local_put(outputPointer, outputData);

    // optional KV write (non-critical)
    try {
      await fetch(KV_RPC, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "kv_put",
          params: [STREAM_ID, outputPointer, outputData],
        }),
      });
    } catch {}

    const outputHash = ethers.keccak256(ethers.toUtf8Bytes(outputData));

    const outputType = await agent.getOutputType();

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

    console.log("RECEIPT:", receipt.status === 1 ? "✓ DONE" : "✗ FAIL");
  } catch (e) {
    console.log("EXEC ERROR:", e.shortMessage || e.message);

    nonce = await provider.getTransactionCount(signer.address, "pending");
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
      } catch {
        continue;
      }

      for (const key of pending) {
        await execute(agentAddr, key);
      }
    } catch {}
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
