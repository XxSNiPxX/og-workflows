const { ethers } = require("ethers");
const fs = require("fs");

// ---------- CONFIG ----------

const wallets = JSON.parse(fs.readFileSync("./deployments/wallets.json"));
const deployed = JSON.parse(fs.readFileSync("../deployments/galileo.json"));

const RPC = "https://rpc.ankr.com/0g_galileo_testnet_evm";

// ---------- SETUP ----------

const provider = new ethers.JsonRpcProvider(RPC);
const signer = new ethers.Wallet(wallets.users[0].privateKey, provider);

const workflowAddress = deployed.workflows[0];

const wfJson = require("/home/snip/Projects/web3/hello_foundry/out/WorkflowInstance.sol/WorkflowInstance.json");

const workflow = new ethers.Contract(workflowAddress, wfJson.abi, signer);

const inft = new ethers.Contract(
  deployed.inft,
  [
    "function ownerOf(uint256) view returns (address)",
    "function isAuthorized(uint256,address) view returns (bool)",
    "function tokenIdOf(address) view returns (uint256)",
  ],
  signer,
);

// ---------- HELPERS ----------

async function tryCall(label, tx) {
  try {
    const res = await provider.call(tx);
    console.log(`\n[${label}] SUCCESS`);
    console.log("return:", res);
  } catch (e) {
    console.log(`\n[${label}] FAIL`);
    console.log("message:", e.message);

    if (e.data) {
      console.log("raw revert data:", e.data);
    } else {
      console.log("raw revert data: NONE");
    }

    // try decode
    try {
      const iface = new ethers.Interface(wfJson.abi);
      const decoded = iface.parseError(e.data);
      console.log("decoded error:", decoded);
    } catch {
      console.log("decode failed");
    }
  }
}

// ---------- MAIN ----------

async function main() {
  console.log("User:", signer.address);

  const tokenId = await inft.tokenIdOf(signer.address);
  console.log("tokenId:", tokenId.toString());

  const owner = await inft.ownerOf(tokenId);
  const isAuth = await inft.isAuthorized(tokenId, workflowAddress);

  console.log("owner:", owner);
  console.log("caller:", signer.address);
  console.log("isAuthorized:", isAuth);

  // ---------- CODE CHECK ----------

  const code = await provider.getCode(workflowAddress);
  console.log("\n--- CODE CHECK ---");
  console.log("code length:", code.length);

  // ---------- SELECTOR CHECK ----------

  const selector = workflow.interface.getFunction("start").selector;
  console.log("\n--- SELECTOR ---");
  console.log("start selector:", selector);

  // ---------- COST ----------

  const cost = await workflow.totalCost();
  console.log("\n--- COST ---");
  console.log("cost:", cost.toString());

  // ---------- INPUT VARIANTS ----------

  const inputs = {
    HASH_INPUT: ethers.id("input"),
    ZERO_HASH: ethers.ZeroHash,
    STRING_ENCODED: ethers.AbiCoder.defaultAbiCoder().encode(
      ["string"],
      ["input"],
    ),
    EMPTY_BYTES: "0x",
  };

  // ---------- TEST CALLS ----------

  console.log("\n--- RAW CALL TESTS ---");

  for (const [name, input] of Object.entries(inputs)) {
    const data = workflow.interface.encodeFunctionData("start", [
      tokenId,
      input,
    ]);

    await tryCall(name, {
      to: workflowAddress,
      data,
      value: cost,
    });
  }

  // ---------- VALUE VARIATION ----------

  console.log("\n--- VALUE TESTS ---");

  const data = workflow.interface.encodeFunctionData("start", [
    tokenId,
    ethers.ZeroHash,
  ]);

  await tryCall("EXACT_COST", {
    to: workflowAddress,
    data,
    value: cost,
  });

  await tryCall("DOUBLE_COST", {
    to: workflowAddress,
    data,
    value: cost * 2n,
  });

  await tryCall("ZERO_COST", {
    to: workflowAddress,
    data,
    value: 0,
  });
  console.log(
    "encoded selector:",
    workflow.interface
      .encodeFunctionData("start", [1, ethers.ZeroHash])
      .slice(0, 10),
  );
  console.log("\nDONE");
}

main().catch((e) => {
  console.error("FATAL:", e.message || e);
});
