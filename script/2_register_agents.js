const { ethers } = require("ethers");
const fs = require("fs");

// ---------------- CONFIG ----------------

const artifact = require("/home/snip/Projects/web3/hello_foundry/out/AgentFactory.sol/AgentFactory.json");
const ABI = artifact.abi;

const wallets = JSON.parse(fs.readFileSync("./deployments/wallets.json"));
const deployedPath = "../deployments/galileo.json";
const deployed = JSON.parse(fs.readFileSync(deployedPath));

if (!deployed.agentFactory) {
  throw new Error("agentFactory missing");
}

// ---------------- PROVIDER ----------------

const provider = new ethers.JsonRpcProvider(wallets.rpc);
const signer = new ethers.Wallet(wallets.agents[0].privateKey, provider);

const factory = new ethers.Contract(deployed.agentFactory, ABI, signer);

// ---------------- UTILS ----------------
async function setWorkflowFactoryOnAgents(agents) {
  console.log("\n--- SET WORKFLOW FACTORY ---");

  if (!deployed.workflowFactory) {
    throw new Error("workflowFactory missing in galileo.json");
  }

  const wf = deployed.workflowFactory;

  const permAbi = [
    "function setWorkflowFactory(address)",
    "function getWorkflowFactory() view returns (address)",
  ];

  for (const a of agents) {
    if (!a || !a.diamond) continue;

    const agent = new ethers.Contract(a.diamond, permAbi, signer);

    console.log("\nAgent:", a.diamond);

    const current = await agent.getWorkflowFactory();
    console.log("Current:", current);

    if (current.toLowerCase() === wf.toLowerCase()) {
      console.log("✓ already set");
      continue;
    }

    const tx = await agent.setWorkflowFactory(wf, {
      gasLimit: 500_000,
    });

    console.log("TX →", tx.hash);

    const receipt = await tx.wait();

    if (receipt.status === 0) {
      throw new Error("setWorkflowFactory failed");
    }

    console.log("✓ set");
  }
}
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

// ---------------- EVENT PARSER ----------------

const iface = new ethers.Interface(ABI);

function extractAgent(receipt) {
  for (const log of receipt.logs) {
    try {
      const parsed = iface.parseLog(log);

      if (parsed.name === "AgentCreated") {
        return {
          id: parsed.args.id.toString(),
          diamond: parsed.args.diamond,
        };
      }
    } catch {}
  }
  return null;
}

// ---------------- PARAMS ----------------

function buildParams(input, output, cost) {
  return {
    name: "agent",
    description: "",
    manifestHash: ethers.ZeroHash,
    inputTypes: [input],
    outputType: output,
    costPerRequest: cost,
    payoutAddress: signer.address,
    workflowReady: true,
  };
}

// ---------------- CREATE ----------------

async function createAgent(input, output, cost) {
  const params = buildParams(input, output, cost);

  console.log("\n--- CREATE AGENT ---");
  console.log(params);

  // -------- STATIC CHECK --------

  try {
    await factory.createAgent.staticCall(params);
    console.log("✓ Static OK");
  } catch (e) {
    console.error("REVERT DATA →", e.data);
    throw e;
  }

  // -------- GAS / NONCE (KEEP EXACT BEHAVIOR) --------

  const fee = await provider.getFeeData();
  const nonce = await provider.getTransactionCount(signer.address, "latest");

  // -------- SEND --------

  const tx = await factory.createAgent(params, {
    maxFeePerGas: fee.maxFeePerGas,
    maxPriorityFeePerGas: fee.maxPriorityFeePerGas,
    gasLimit: 4_000_000,
    nonce,
  });

  console.log("TX SENT →", tx.hash);

  // -------- VERIFY BROADCAST --------

  await sleep(2000);
  const seen = await provider.getTransaction(tx.hash);

  if (!seen) {
    throw new Error("TX NOT BROADCAST (RPC dropped it)");
  }

  console.log("✓ Broadcast visible");

  // -------- WAIT --------

  const receipt = await waitForReceipt(tx.hash);

  if (!receipt) {
    console.log("⚠ NOT INCLUDED (stuck or dropped)");
    return null;
  }

  if (receipt.status === 0) {
    throw new Error("TX FAILED (reverted)");
  }

  console.log("✓ INCLUDED → block", receipt.blockNumber);

  // -------- EXTRACT RESULT --------

  const agent = extractAgent(receipt);

  if (!agent) {
    console.log("⚠ AgentCreated event not found");
    return null;
  }

  console.log("✓ AGENT CREATED →", agent);

  return agent;
}

// ---------------- MAIN ----------------

async function main() {
  console.log("Signer:", signer.address);
  console.log("Factory:", deployed.agentFactory);

  const code = await provider.getCode(deployed.agentFactory);
  if (code === "0x") throw new Error("Factory missing");

  console.log("✓ Factory code exists");

  const net = await provider.getNetwork();
  console.log("ChainId:", net.chainId);

  const block = await provider.getBlockNumber();
  console.log("Current block:", block);

  // -------- EXECUTION --------

  const agents = [];

  agents.push(
    await createAgent(
      ethers.id("txt"),
      ethers.id("emb"),
      ethers.parseEther("0.01"),
    ),
  );

  agents.push(
    await createAgent(
      ethers.id("emb"),
      ethers.id("vec"),
      ethers.parseEther("0.02"),
    ),
  );

  agents.push(
    await createAgent(
      ethers.id("vec"),
      ethers.id("report"),
      ethers.parseEther("0.03"),
    ),
  );

  console.log("\n--- AGENTS ---");
  console.log(agents);

  // -------- SAVE --------

  const clean = agents.filter((a) => a !== null);

  deployed.agents = clean;

  fs.writeFileSync(deployedPath, JSON.stringify(deployed, null, 2));

  console.log("✓ Saved agents →", deployedPath);
  console.log("\nDONE");
}

main().catch((e) => {
  console.error("FATAL:", e.message || e);
  process.exit(1);
});
