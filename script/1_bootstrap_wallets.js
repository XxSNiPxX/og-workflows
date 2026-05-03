const { ethers } = require("ethers");
const fs = require("fs");

const RPC = "https://rpc.ankr.com/0g_galileo_testnet_evm";

// 🔴 TEST KEY ONLY
const FUNDER_PK = "REPLACE_HERE";

const provider = new ethers.JsonRpcProvider(RPC);
const funder = new ethers.Wallet(FUNDER_PK, provider);

// CONFIG
const NUM_USERS = 5;
const NUM_AGENTS = 3;
const FUND_AMOUNT = ethers.parseEther("0.2");
const GAS_PRICE = ethers.parseUnits("4", "gwei");
const CONFIRM_TIMEOUT = 20000; // 20s
const MAX_RETRIES = 3;

const wallets = {
  users: [],
  agents: [],
};

function createWallet() {
  return ethers.Wallet.createRandom();
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// --------------------------------------------------
// SEND TX WITH RETRIES + TIMEOUT
// --------------------------------------------------

async function sendWithRetry(txData, nonce) {
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      const tx = await funder.sendTransaction({
        ...txData,
        nonce,
        gasPrice: GAS_PRICE, // 🔴 FORCE for 0G
      });

      console.log(`TX SENT [${attempt}] →`, tx.hash);

      // wait with timeout
      const receipt = await Promise.race([
        tx.wait(),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error("timeout")), CONFIRM_TIMEOUT),
        ),
      ]);

      console.log("CONFIRMED →", tx.hash);
      return receipt;
    } catch (err) {
      console.log(`Retry ${attempt} failed:`, err.message);

      if (attempt === MAX_RETRIES) {
        throw err;
      }

      await sleep(2000 * attempt);
    }
  }
}

// --------------------------------------------------
// MAIN
// --------------------------------------------------

async function main() {
  console.log("Funder:", funder.address);

  // ensure deployments dir exists
  if (!fs.existsSync("./deployments")) {
    fs.mkdirSync("./deployments");
  }

  // create wallets
  for (let i = 0; i < NUM_USERS; i++) {
    wallets.users.push(createWallet());
  }

  for (let i = 0; i < NUM_AGENTS; i++) {
    wallets.agents.push(createWallet());
  }

  const allWallets = [...wallets.users, ...wallets.agents];

  // get starting nonce
  let nonce = await provider.getTransactionCount(funder.address);

  console.log("Starting nonce:", nonce);

  // fund wallets
  for (const w of allWallets) {
    console.log("Funding:", w.address);

    await sendWithRetry(
      {
        to: w.address,
        value: FUND_AMOUNT,
      },
      nonce,
    );

    nonce++; // 🔴 manual nonce control
  }

  // save wallets
  const out = {
    rpc: RPC,
    users: wallets.users.map((w) => ({
      address: w.address,
      privateKey: w.privateKey,
    })),
    agents: wallets.agents.map((w) => ({
      address: w.address,
      privateKey: w.privateKey,
    })),
  };

  fs.writeFileSync("./deployments/wallets.json", JSON.stringify(out, null, 2));

  console.log("Saved → deployments/wallets.json");
}

main().catch((e) => {
  console.error("FATAL:", e);
  process.exit(1);
});
