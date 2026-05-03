const { ethers } = require("ethers");
const fs = require("fs");

// ---------------- CONFIG ----------------

const wallets = JSON.parse(fs.readFileSync("./deployments/wallets.json"));
const deployed = JSON.parse(fs.readFileSync("../deployments/galileo.json"));

const provider = new ethers.JsonRpcProvider(wallets.rpc);

// ---------------- ABIS ----------------

const manifestAbi =
  require("/home/snip/Projects/web3/hello_foundry/out/AgentManifestFacet.sol/AgentManifestFacet.json").abi;
const permissionAbi =
  require("/home/snip/Projects/web3/hello_foundry/out/AgentPermissionFacet.sol/AgentPermissionFacet.json").abi;
const executionAbi =
  require("/home/snip/Projects/web3/hello_foundry/out/AgentExecutionFacet.sol/AgentExecutionFacet.json").abi;
const adminAbi =
  require("/home/snip/Projects/web3/hello_foundry/out/AgentAdminFacet.sol/AgentAdminFacet.json").abi;

const registryAbi =
  require("/home/snip/Projects/web3/hello_foundry/out/AgentRegistry.sol/AgentRegistry.json").abi;

// ---------------- UTILS ----------------

function ok(msg, val) {
  console.log(`✓ ${msg}:`, val);
}

function fail(msg, err) {
  console.log(`✗ ${msg}`);
  console.log("  →", err.shortMessage || err.message || err);
}

// ---------------- LOW LEVEL SELECTOR TEST ----------------

async function testSelectors(addr) {
  console.log("\n--- SELECTOR ROUTING ---");

  const selectors = {
    owner: "0x8da5cb5b",
    joinWorkflow: ethers.id("joinWorkflow(address)").slice(0, 10),
    setWorkflowFactory: ethers.id("setWorkflowFactory(address)").slice(0, 10),
    getWorkflowFactory: ethers.id("getWorkflowFactory()").slice(0, 10),
  };

  for (const [name, sel] of Object.entries(selectors)) {
    try {
      await provider.call({ to: addr, data: sel });
      ok(`selector ${name}`, sel);
    } catch (e) {
      fail(`selector ${name}`, sel);
    }
  }
}

// ---------------- AGENT TEST ----------------

async function testAgent(addr, registry) {
  console.log("\n====================================");
  console.log("AGENT:", addr);
  console.log("====================================");

  const manifest = new ethers.Contract(addr, manifestAbi, provider);
  const perm = new ethers.Contract(addr, permissionAbi, provider);
  const exec = new ethers.Contract(addr, executionAbi, provider);
  const admin = new ethers.Contract(addr, adminAbi, provider);

  // ---------- MANIFEST ----------
  let inputs = [];
  let output;

  try {
    const m = await manifest.getManifest();
    ok("createdAt", m.createdAt.toString());
    ok("workflowReady", m.workflowReady);
  } catch (e) {
    fail("getManifest", e);
  }

  try {
    inputs = await manifest.getInputTypes();
    ok("inputs", inputs);
  } catch (e) {
    fail("getInputTypes", e);
  }

  try {
    output = await manifest.getOutputType();
    ok("output", output);
  } catch (e) {
    fail("getOutputType", e);
  }

  // ---------- PERMISSION ----------
  try {
    const wf = await perm.getWorkflowFactory();
    ok("workflowFactory", wf);
  } catch (e) {
    fail("getWorkflowFactory", e);
  }

  try {
    const trusted = await perm.isTrustedCaller(addr);
    ok("self trusted?", trusted);
  } catch (e) {
    fail("isTrustedCaller", e);
  }

  // ---------- EXECUTION ----------
  try {
    const cfg = await exec.getExecutionConfig();
    ok("executionConfig", cfg);
  } catch (e) {
    fail("executionConfig", e);
  }

  try {
    const paused = await manifest.isPaused();
    ok("paused", paused);
  } catch (e) {
    fail("paused", e);
  }

  // ---------- ADMIN ----------
  try {
    const a = await admin.admin();
    ok("admin", a);
  } catch (e) {
    fail("admin", e);
  }

  // ---------- REGISTRY ----------
  try {
    const id = await registry.agentIdByAddress(addr);
    ok("registryId", id.toString());

    if (id != 0n) {
      const rec = await registry.getAgent(id);
      ok("registry.active", rec.active);
      ok("registry.workflowReady", rec.workflowReady);
    }
  } catch (e) {
    fail("registry lookup", e);
  }

  // ---------- SELECTOR TEST ----------
  await testSelectors(addr);

  return { addr, inputs, output };
}

// ---------------- PIPELINE VALIDATION ----------------

function validatePipeline(agents) {
  console.log("\n=== PIPELINE VALIDATION ===");

  for (let i = 0; i < agents.length; i++) {
    const a = agents[i];

    if (a.inputs.length === 0) {
      throw new Error(`Agent ${a.addr} has no inputs`);
    }

    if (i > 0) {
      const prev = agents[i - 1];

      const match = a.inputs.find((x) => x === prev.output);

      if (!match) {
        throw new Error(
          `CHAIN BROKEN\n${prev.addr} → ${a.addr}\nexpected: ${prev.output}\navailable: ${a.inputs}`,
        );
      }

      ok(`chain ${i - 1} → ${i}`, "valid");
    }
  }

  console.log("✓ pipeline valid\n");
}

// ---------------- MAIN ----------------

async function main() {
  if (!deployed.agents || deployed.agents.length === 0) {
    throw new Error("No agents found");
  }

  console.log(
    "Agents:",
    deployed.agents.map((a) => a.diamond),
  );

  const registry = new ethers.Contract(
    deployed.agentRegistry,
    registryAbi,
    provider,
  );

  const results = [];

  for (const a of deployed.agents) {
    if (!a || !a.diamond) continue;

    const res = await testAgent(a.diamond, registry);
    results.push(res);
  }

  // ---------- PIPELINE CHECK ----------
  try {
    validatePipeline(results);
  } catch (e) {
    console.log("\n✗ PIPELINE INVALID");
    console.log(e.message);
  }

  console.log("\nDONE");
}

main().catch((e) => {
  console.error("FATAL:", e);
  process.exit(1);
});
