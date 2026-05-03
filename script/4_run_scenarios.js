const { ethers } = require("ethers");
const fs = require("fs");

// ---------------- CONFIG ----------------

const wallets = JSON.parse(fs.readFileSync("./deployments/wallets.json"));
const deployed = JSON.parse(fs.readFileSync("../deployments/galileo.json"));

const RPC = "https://rpc.ankr.com/0g_galileo_testnet_evm";

// ---------------- PROVIDER ----------------

const provider = new ethers.JsonRpcProvider(RPC);
const signer = new ethers.Wallet(wallets.users[0].privateKey, provider);

// ---------------- INTERFACE ----------------

const wfJson = require("/home/snip/Projects/web3/hello_foundry/out/WorkflowInstance.sol/WorkflowInstance.json");
const iface = new ethers.Interface(wfJson.abi);

const workflowAddress = deployed.workflows[0];

// ---------------- INFT ----------------

const inft = new ethers.Contract(
  deployed.inft,
  [
    "function mint(address,bytes32,bytes,string) returns (uint256)",
    "function authorizeUsage(uint256,address,bytes)",
    "function isAuthorized(uint256,address) view returns (bool)",
    "function tokenIdOf(address) view returns (uint256)",
  ],
  signer,
);

// ---------------- TX ENGINE ----------------

async function waitForReceipt(hash, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const r = await provider.getTransactionReceipt(hash);
    if (r) return r;
    await new Promise((r) => setTimeout(r, 1500));
  }
  return null;
}

async function sendTx(txBase, label) {
  console.log(`\n=== ${label} ===`);

  const nonce = await provider.getTransactionCount(signer.address, "latest");
  console.log("nonce:", nonce);

  let fee = ethers.parseUnits("30", "gwei");
  let tip = ethers.parseUnits("6", "gwei");

  for (let i = 0; i < 5; i++) {
    console.log(`attempt ${i}`);

    const tx = await signer.sendTransaction({
      ...txBase,
      nonce,
      maxFeePerGas: fee,
      maxPriorityFeePerGas: tip,
    });

    console.log("TX:", tx.hash);

    const receipt = await waitForReceipt(tx.hash, 12000);

    if (receipt) {
      if (receipt.status === 0) throw new Error(`${label} reverted`);
      console.log("✓ block:", receipt.blockNumber);
      return receipt;
    }

    console.log("⚠ rebroadcast");
    fee = (fee * 14n) / 10n;
    tip = (tip * 14n) / 10n;
  }

  throw new Error(`${label} stuck`);
}

// ---------------- HARD CHECKS ----------------

async function verifyWorkflowContract() {
  console.log("\n--- VERIFY CONTRACT ---");

  const code = await provider.getCode(workflowAddress);
  console.log("code length:", code.length);

  if (code === "0x") {
    throw new Error("❌ No contract at workflowAddress");
  }

  const selector = iface.encodeFunctionData("totalCost").slice(0, 10);
  console.log("expected totalCost selector:", selector);

  try {
    const res = await provider.call({
      to: workflowAddress,
      data: selector,
    });

    console.log("totalCost raw response:", res);

    return ethers.toBigInt(res);
  } catch (e) {
    console.log("\n❌ totalCost() FAILED");
    console.log("message:", e.message);

    throw new Error(`
Workflow contract mismatch:

- Address: ${workflowAddress}
- Selector: ${selector}

This contract does NOT implement totalCost().
Likely causes:
1. Wrong address in deployments file
2. Diamond/proxy missing selector
3. ABI mismatch with deployed bytecode
`);
  }
}

// ---------------- MINT ----------------

async function ensureMint() {
  console.log("\n--- MINT ---");

  let tokenId = await inft.tokenIdOf(signer.address);

  if (tokenId !== 0n) {
    console.log("✓ tokenId:", tokenId.toString());
    return tokenId;
  }

  const data = inft.interface.encodeFunctionData("mint", [
    signer.address,
    ethers.ZeroHash,
    ethers.toUtf8Bytes("key"),
    "ipfs://dummy",
  ]);

  await sendTx({ to: deployed.inft, data, gasLimit: 300000n }, "MINT");

  tokenId = await inft.tokenIdOf(signer.address);
  console.log("✓ tokenId:", tokenId.toString());

  return tokenId;
}

// ---------------- AUTHORIZE ----------------

async function ensureAuthorization(tokenId) {
  console.log("\n--- AUTH ---");

  const isAuth = await inft.isAuthorized(tokenId, workflowAddress);
  console.log("isAuthorized(workflow):", isAuth);

  if (isAuth) return;

  const permission = ethers.AbiCoder.defaultAbiCoder().encode(
    ["tuple(bool,bool,bool,bytes32[],uint256[],uint64)"],
    [[true, true, false, [], [], 9999999999]],
  );

  const data = inft.interface.encodeFunctionData("authorizeUsage", [
    tokenId,
    workflowAddress,
    permission,
  ]);

  await sendTx({ to: deployed.inft, data, gasLimit: 300000n }, "AUTHORIZE");

  const after = await inft.isAuthorized(tokenId, workflowAddress);
  console.log("after:", after);

  if (!after) throw new Error("Authorization failed");
}

// ---------------- START ----------------

async function startWorkflow(tokenId, cost) {
  console.log("\n--- START ---");

  const data = iface.encodeFunctionData("start", [tokenId, ethers.ZeroHash]);

  console.log("start selector:", data.slice(0, 10));

  // simulate
  try {
    await provider.call({
      to: workflowAddress,
      data,
      value: cost,
    });
    console.log("✓ simulation passed");
  } catch (e) {
    console.log("\n❌ SIMULATION FAILED");
    console.log("message:", e.message);
    throw e;
  }

  await sendTx(
    {
      to: workflowAddress,
      data,
      value: cost,
      gasLimit: 500000n,
    },
    "START",
  );
}

// ---------------- MAIN ----------------

async function main() {
  console.log("User:", signer.address);

  // 🔴 HARD VERIFY CONTRACT FIRST
  const cost = await verifyWorkflowContract();

  console.log("verified cost:", cost.toString());

  const tokenId = await ensureMint();
  await ensureAuthorization(tokenId);
  await startWorkflow(tokenId, cost);

  console.log("\nDONE");
}

main().catch((e) => {
  console.error("\nFATAL:", e.message || e);
});
