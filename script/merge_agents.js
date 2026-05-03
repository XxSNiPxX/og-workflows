const fs = require("fs");

const mainPath = "../deployments/galileo.json";
const newPath = "../deployments/agents_new.json";

const main = JSON.parse(fs.readFileSync(mainPath));
const incoming = JSON.parse(fs.readFileSync(newPath));

if (!main.agents) main.agents = [];

const existing = new Set(main.agents.map((a) => a.diamond.toLowerCase()));

for (const a of incoming.agents || []) {
  if (existing.has(a.diamond.toLowerCase())) {
    console.log("skip duplicate:", a.diamond);
    continue;
  }

  main.agents.push({
    id: a.id.toString(),
    diamond: a.diamond,
  });

  console.log("added:", a.diamond);
}

fs.writeFileSync(mainPath, JSON.stringify(main, null, 2));

console.log("\n✓ merged into galileo.json");
