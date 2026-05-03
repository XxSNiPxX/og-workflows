const { ethers } = require("ethers");

// ---------------- CONFIG ----------------

const RPC = "https://rpc.ankr.com/0g_galileo_testnet_evm";

const PRIVATE_KEY =
  "0x1b51248222c14b14ecc1fc94680803064894f5cc443b30e71f797dda72e2ac41";

const provider = new ethers.JsonRpcProvider(RPC);
const signer = new ethers.Wallet(PRIVATE_KEY, provider);

// addresses
const AGENT = "0x261767A1EfE1048717AAafe0eb807F10C3Da99b4";
const WORKFLOW_FACTORY = "0x5A172e5401839C058cE326A33edFb11025e33532";
const REGISTRY = "0xd6b4df99D68c3F6d58A35ad61acd09695d37AF5e";

// ---------------- MAIN ----------------

async function main() {
  console.log("\n================ FULL SYSTEM DEBUG ================\n");

  // ------------------------------------------------
  // 1. INTERFACE (SOURCE OF TRUTH)
  // ------------------------------------------------

  const iface = new ethers.Interface([
    "function joinWorkflow(address)",
    "function setWorkflowFactory(address)",
  ]);

  const JOIN_SELECTOR = iface.getFunction("joinWorkflow").selector;
  const SET_SELECTOR = iface.getFunction("setWorkflowFactory").selector;

  console.log("--- SELECTOR CHECK ---");
  console.log("joinWorkflow:", JOIN_SELECTOR);
  console.log("setWorkflowFactory:", SET_SELECTOR);

  // ------------------------------------------------
  // 2. DIAMOND ROUTING
  // ------------------------------------------------

  const loupe = new ethers.Contract(
    AGENT,
    ["function facetAddress(bytes4) view returns (address)"],
    provider,
  );

  console.log("\n--- DIAMOND ROUTING ---");

  const joinFacet = await loupe.facetAddress(JOIN_SELECTOR);
  const setFacet = await loupe.facetAddress(SET_SELECTOR);

  console.log("joinWorkflow →", joinFacet);
  console.log("setWorkflowFactory →", setFacet);

  if (joinFacet === ethers.ZeroAddress) {
    throw new Error("joinWorkflow NOT WIRED");
  }

  // ------------------------------------------------
  // 3. REGISTRY CHECK (FIXED ABI)
  // ------------------------------------------------

  console.log("\n--- REGISTRY CHECK ---");

  const registry = new ethers.Contract(
    REGISTRY,
    [
      "function agentIdByAddress(address) view returns (uint256)",
      `function getAgent(uint256) view returns (
        tuple(
          uint256 agentId,
          address agentAddress,
          address creator,
          address admin,
          address payoutAddress,
          bytes32[] inputTypes,
          bytes32 outputType,
          uint256 costPerRequest,
          bool workflowReady,
          bool active,
          uint64 createdAt,
          uint64 updatedAt,
          string name,
          string description,
          bytes32 manifestHash
        )
      )`,
    ],
    provider,
  );

  const agentId = await registry.agentIdByAddress(AGENT);
  console.log("Agent ID:", agentId.toString());

  const rec = await registry.getAgent(agentId);

  console.log("Agent Address:", rec.agentAddress);
  console.log("Active:", rec.active);
  console.log("Workflow Ready:", rec.workflowReady);

  if (rec.agentAddress.toLowerCase() !== AGENT.toLowerCase()) {
    throw new Error("Registry mismatch (agentAddress incorrect)");
  }

  if (!rec.active) {
    console.log("✗ Agent is NOT active");
  }

  if (!rec.workflowReady) {
    console.log("✗ Agent is NOT workflowReady");
  }

  // ------------------------------------------------
  // 4. PERMISSION STATE
  // ------------------------------------------------

  console.log("\n--- PERMISSION STATE ---");

  const perm = new ethers.Contract(
    AGENT,
    [
      "function getWorkflowFactory() view returns (address)",
      "function isTrustedCaller(address) view returns (bool)",
    ],
    provider,
  );

  const storedFactory = await perm.getWorkflowFactory();
  console.log("Stored workflowFactory:", storedFactory);

  const isTrusted = await perm.isTrustedCaller(WORKFLOW_FACTORY);
  console.log("Factory trusted?:", isTrusted);

  // ------------------------------------------------
  // 5. DIRECT CALL (EOA)
  // ------------------------------------------------

  console.log("\n--- DIRECT CALL (EOA) ---");

  const callData = iface.encodeFunctionData("joinWorkflow", [
    "0x0000000000000000000000000000000000000001",
  ]);

  try {
    const tx = await signer.sendTransaction({
      to: AGENT,
      data: callData,
      gasLimit: 300000,
    });

    console.log("✓ direct call tx:", tx.hash);
  } catch (e) {
    console.log("✗ direct call failed");
    console.log("→", e.shortMessage || e.message);
  }

  // ------------------------------------------------
  // 6. FACTORY CONSISTENCY CHECK
  // ------------------------------------------------

  console.log("\n--- FACTORY AUTH CHECK ---");

  if (storedFactory.toLowerCase() !== WORKFLOW_FACTORY.toLowerCase()) {
    console.log("✗ CRITICAL: factory mismatch");
    console.log("Agent expects:", storedFactory);
    console.log("You are using:", WORKFLOW_FACTORY);
  } else {
    console.log("✓ Factory matches agent");
  }
  // ------------------------------------------------
  // 8. FACTORY DIAMOND DEEP INSPECTION
  // ------------------------------------------------

  console.log("\n--- FACTORY DEEP INSPECTION ---");

  // minimal loupe ABI
  const factoryLoupe = new ethers.Contract(
    WORKFLOW_FACTORY,
    [
      "function facetAddress(bytes4) view returns (address)",
      "function facetAddresses() view returns (address[])",
      "function facetFunctionSelectors(address) view returns (bytes4[])",
    ],
    provider,
  );

  // --- 8.1 Check createWorkflow selector routing

  const factoryIface = new ethers.Interface([
    "function createWorkflow((address,bytes32,bytes32)[],string,string,address)",
  ]);

  const CREATE_SELECTOR = factoryIface.getFunction("createWorkflow").selector;

  console.log("\n[Selector]");
  console.log("createWorkflow:", CREATE_SELECTOR);

  let createFacet;
  try {
    createFacet = await factoryLoupe.facetAddress(CREATE_SELECTOR);
    console.log("Facet for createWorkflow:", createFacet);
  } catch (e) {
    console.log("facetAddress failed →", e.message);
  }

  // --- 8.2 List ALL facets

  let facets = [];
  try {
    facets = await factoryLoupe.facetAddresses();
    console.log("\n[Facets]");
    console.log(facets);
  } catch (e) {
    console.log("facetAddresses() not supported");
  }

  // --- 8.3 Dump selectors per facet

  for (const f of facets) {
    try {
      const selectors = await factoryLoupe.facetFunctionSelectors(f);

      console.log(`\nFacet: ${f}`);
      console.log("Selectors count:", selectors.length);

      // print first few
      console.log("Sample:", selectors.slice(0, 5));
    } catch (e) {
      console.log(`Failed reading selectors for ${f}`);
    }
  }

  // --- 8.4 Brute scan for selector presence

  let found = false;

  for (const f of facets) {
    try {
      const selectors = await factoryLoupe.facetFunctionSelectors(f);

      if (selectors.includes(CREATE_SELECTOR)) {
        console.log("\n✓ FOUND createWorkflow in facet:", f);
        found = true;
      }
    } catch {}
  }

  if (!found) {
    console.log("\n✗ createWorkflow selector NOT found in ANY facet");
  }

  // ------------------------------------------------
  // 9. RAW FALLBACK TEST (LOW LEVEL)
  // ------------------------------------------------

  console.log("\n--- RAW FALLBACK TEST ---");

  try {
    const data = CREATE_SELECTOR; // selector only, no args

    const res = await provider.call({
      to: WORKFLOW_FACTORY,
      data,
    });

    console.log("Unexpected success:", res);
  } catch (e) {
    console.log("Fallback revert:");
    console.log("→", e.shortMessage || e.message);
  }
  // ------------------------------------------------
  // 7. SIMULATED FACTORY CALL
  // ------------------------------------------------

  console.log("\n--- ERROR DECODE ---");

  const errIface = new ethers.Interface([
    "error NotWorkflowFactory()",
    "error AgentPaused(uint256,address)",
    "error AgentNotWorkflowReady(uint256,address)",
  ]);

  try {
    await provider.call({
      to: AGENT,
      from: WORKFLOW_FACTORY,
      data: callData,
    });

    console.log("✓ factory call WOULD succeed");
  } catch (e) {
    const data = e.data || e.info?.error?.data;

    console.log("Raw error:", data);

    try {
      const decoded = errIface.parseError(data);
      console.log("Decoded error:", decoded.name);
    } catch {
      console.log("Unknown error selector:", data?.slice(0, 10));
    }
  }

  console.log("\n=================================================\n");
}

main().catch((e) => {
  console.error("FATAL:", e);
  process.exit(1);
});
