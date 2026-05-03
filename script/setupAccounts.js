import { ethers } from "ethers";
import fs from "fs";

const RPC = "https://rpc.ankr.com/0g_galileo_testnet_evm";

// 🔴 your funded deployer key
const DEPLOYER_PK = "0xYOUR_PRIVATE_KEY";

const NUM_USERS = 3;
const NUM_AGENTS = 2;

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const deployer = new ethers.Wallet(DEPLOYER_PK, provider);

  console.log("Deployer:", deployer.address);

  const users = [];
  const agents = [];

  // generate wallets
  for (let i = 0; i < NUM_USERS; i++) {
    const w = ethers.Wallet.createRandom();
    users.push(w);
  }

  for (let i = 0; i < NUM_AGENTS; i++) {
    const w = ethers.Wallet.createRandom();
    agents.push(w);
  }

  // fund them
  for (const w of [...users, ...agents]) {
    const tx = await deployer.sendTransaction({
      to: w.address,
      value: ethers.parseEther("0.2"),
    });
    await tx.wait();
    console.log("Funded:", w.address);
  }

  // save
  const data = {
    users: users.map((w) => ({ address: w.address, pk: w.privateKey })),
    agents: agents.map((w) => ({ address: w.address, pk: w.privateKey })),
  };

  fs.writeFileSync("./actors.json", JSON.stringify(data, null, 2));

  console.log("Saved to actors.json");
}

main();
