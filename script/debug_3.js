const { ethers } = require("ethers");

// ---------------- CONFIG ----------------

const RPC = "https://rpc.ankr.com/0g_galileo_testnet_evm";

const provider = new ethers.JsonRpcProvider(RPC);

const FACTORY = "0x498647D9A4d988Ff49a8dAc6293D42c090E63023";
const USER = "0xD6A05c102E9979d466714EFBC36aBf982088Fd04";

const AGENTS = [
  "0xe976adF1595cB3a65F233B05950872d5874aFcF5",
  "0x8A32eb37E8a95800e1E54dC024387C1bD1BE0871",
];

// ---------------- ABIs ----------------

const loupeAbi = ["function facetAddress(bytes4) view returns (address)"];

const agentAbi = [
  "function getInputTypes() view returns (bytes32[])",
  "function getOutputType() view returns (bytes32)",
  "function supportsInput(bytes32) view returns (bool)",
  "function isPaused() view returns (bool)",
  "function payoutAddress() view returns (address)",
  "function quote() view returns (uint256)",

  "function getWorkflowFactory() view returns (address)",
  "function isTrustedCaller(address) view returns (bool)",

  "function joinWorkflow(address)",
];

// ---------------- HELPERS ----------------

function sel(sig) {
  return ethers.id(sig).slice(0, 10);
}

// ---------------- MAIN ----------------

async function main() {
  console.log("\n================ DEEP DEBUG ================\n");

  for (const addr of AGENTS) {
    console.log("\n======================================");
    console.log("AGENT:", addr);

    const loupe = new ethers.Contract(addr, loupeAbi, provider);
    const agent = new ethers.Contract(addr, agentAbi, provider);

    // ------------------------------------------------
    // 1. SELECTOR ROUTING
    // ------------------------------------------------

    console.log("\n--- SELECTOR ROUTING ---");

    const funcs = [
      "isPaused()",
      "supportsInput(bytes32)",
      "getOutputType()",
      "quote()",
      "payoutAddress()",
      "joinWorkflow(address)",
    ];

    for (const f of funcs) {
      const fsel = sel(f);
      const facet = await loupe.facetAddress(fsel);
      console.log(f, "→", facet);
    }

    // ------------------------------------------------
    // 2. DIRECT CALL TESTS (CRITICAL)
    // ------------------------------------------------

    console.log("\n--- DIRECT CALL TESTS ---");

    try {
      const paused = await agent.isPaused();
      console.log("isPaused:", paused);
    } catch (e) {
      console.log("isPaused FAILED →", e.shortMessage);
    }

    let inputs;
    try {
      inputs = await agent.getInputTypes();
      console.log("inputs:", inputs);
    } catch (e) {
      console.log("getInputTypes FAILED →", e.shortMessage);
    }

    let output;
    try {
      output = await agent.getOutputType();
      console.log("output:", output);
    } catch (e) {
      console.log("getOutputType FAILED →", e.shortMessage);
    }

    try {
      const q = await agent.quote();
      console.log("quote:", q.toString());
    } catch (e) {
      console.log("quote FAILED →", e.shortMessage);
    }

    try {
      const payout = await agent.payoutAddress();
      console.log("payoutAddress:", payout);
    } catch (e) {
      console.log("payoutAddress FAILED →", e.shortMessage);
    }

    if (inputs && inputs.length > 0) {
      try {
        const ok = await agent.supportsInput(inputs[0]);
        console.log("supportsInput:", ok);
      } catch (e) {
        console.log("supportsInput FAILED →", e.shortMessage);
      }
    }

    // ------------------------------------------------
    // 3. PERMISSION STATE
    // ------------------------------------------------

    console.log("\n--- PERMISSION ---");

    try {
      const wf = await agent.getWorkflowFactory();
      console.log("workflowFactory:", wf);

      const trusted = await agent.isTrustedCaller(FACTORY);
      console.log("factory trusted?:", trusted);
    } catch (e) {
      console.log("permission read FAILED →", e.shortMessage);
    }

    // ------------------------------------------------
    // 4. JOIN WORKFLOW SIMULATION
    // ------------------------------------------------

    console.log("\n--- JOIN WORKFLOW TEST ---");

    try {
      await provider.call({
        to: addr,
        from: FACTORY,
        data:
          sel("joinWorkflow(address)") +
          "0000000000000000000000000000000000000001".slice(2),
      });

      console.log("joinWorkflow: WOULD SUCCEED");
    } catch (e) {
      console.log("joinWorkflow FAILED →", e.shortMessage || e.message);
    }
  }

  console.log("\n======================================");
  console.log("\nDONE\n");
}

main().catch(console.error);
