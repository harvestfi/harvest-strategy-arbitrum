// Deployer-wallet prep for upgrading the three LIVE Morpho Vault V2 strategies
// (Gauntlet Balanced V2, Gauntlet Prime V2, Steakhouse High Yield V2).
//
// This script performs ONLY the deployer's actions: it deploys the new implementation
// contracts. It does NOT touch the proxies, the positions or governance state. After it
// runs, GOVERNANCE (the Safe) sends the transactions printed at the end, which come from
// scripts/morpho-v2-upgrade-plan.js. test/morpho/v2/upgrade-rehearsal.js runs that same
// plan on a fork.
//
//   npx hardhat run scripts/12-prepare-morpho-v2-upgrade.js --network mainnet
//     1. Deploy the three implementations (or reuse one via GC_IMPL / GP_IMPL / SHHY_IMPL).
//     2. Check that each holds exactly this build's code, and verify it on Arbiscan.
//     3. Print the governance plan and write the Safe Transaction Builder files to OUT
//        (default ./safe-transactions): the list from plan.upgradeFiles().
//
//   ONLY=GC,GP limits the run to those strategies; the others are left as they are.
//   VERIFY_REUSED=1 also re-verifies an implementation that was passed in.
//
//   On --network hardhat this is a dry run against the fork: the implementations it
//   deploys exist nowhere else, so the files it writes are only good for reading.
//
// The proxies already exist and are reused by the upgrade. Nothing here is initialized.

const fs = require("fs");
const path = require("path");
const hre = require("hardhat");
const { type2Transaction } = require("./utils.js");
const plan = require("./morpho-v2-upgrade-plan.js");

const { SAFE, STRATEGIES } = plan;

const proxyAbi = [
  "function implementation() view returns (address)",
  "function governance() view returns (address)",
];

async function verify(label, args) {
  if (hre.network.name === "hardhat") return;
  try {
    await hre.run("verify:verify", args);
  } catch (error) {
    console.log(`   ${label}: verification failed (${String(error.message).split("\n")[0]});`);
    console.log("   re-run with the address and VERIFY_REUSED=1 to retry (the command is printed at the end)");
  }
}

function writeTxBuilderFiles(out, files) {
  fs.mkdirSync(out, { recursive: true });
  for (const { file, description, tx } of files) {
    const f = path.join(out, file);
    fs.writeFileSync(f, JSON.stringify(plan.txBuilderFile(file, description, tx), null, 2));
    console.log(`   wrote ${f} (${tx.calls.length} raw call${tx.calls.length > 1 ? "s" : ""})`);
  }
}

async function main() {
  const provider = hre.ethers.provider;
  const only = (process.env.ONLY || "").split(",").map((key) => key.trim()).filter(Boolean);
  const unknown = only.filter((key) => !STRATEGIES.some((s) => s.key === key));
  if (unknown.length) throw new Error(`ONLY names an unknown strategy: ${unknown.join(", ")}`);
  const targets = STRATEGIES.filter((s) => !only.length || only.includes(s.key));

  // Stop before deploying anything if the chain is not where the plan thinks it is.
  for (const s of targets) {
    if ((await provider.getCode(s.proxy)) === "0x") {
      throw new Error(`${s.farm}: no strategy at ${s.proxy} on this network. On a fork, set the fork block in hardhat.config.js to a recent one.`);
    }
    const proxy = new hre.ethers.Contract(s.proxy, proxyAbi, provider);
    const live = await proxy.implementation();
    if (live !== hre.ethers.utils.getAddress(s.liveImpl)) {
      throw new Error(`${s.farm}: the proxy runs ${live}, not ${s.liveImpl}. Already upgraded? Update scripts/morpho-v2-upgrade-plan.js.`);
    }
    const governance = await proxy.governance();
    if (governance !== SAFE) throw new Error(`${s.farm}: governance is ${governance}, not the Safe ${SAFE}`);
  }

  console.log("New Morpho V2 strategy implementations.");
  const impls = {};
  for (const s of targets) {
    const artifact = await hre.artifacts.readArtifact(s.artifact);
    const reused = process.env[`${s.key}_IMPL`];
    if (reused) {
      impls[s.key] = hre.ethers.utils.getAddress(reused);
      console.log(`${s.farm}: reusing ${impls[s.key]}`);
    } else {
      const Impl = artifacts.require(s.artifact);
      const tx = await type2Transaction(Impl.new);
      impls[s.key] = hre.ethers.utils.getAddress(tx.creates);
      console.log(`${s.farm}: ${s.artifact} deployed at ${impls[s.key]}`);
    }
    // Byte for byte this build, whether it was just deployed or passed in.
    await plan.assertImplMatchesBuild(provider, artifact, impls[s.key]);
    if (!reused || process.env.VERIFY_REUSED) await verify(s.artifact, { address: impls[s.key] });
  }

  // The Transaction Builder files and the txs printed below are the same objects.
  const files = plan.upgradeFiles(impls);
  const [tx1, tx2, rollback] = files.map((f) => f.tx);

  console.log(`\n=== Deployer done. Governance next: Safe ${SAFE} (12h upgrade delay) ===`);
  for (const tx of [tx1, tx2]) {
    console.log(`\n${tx.label}`);
    tx.calls.forEach((call, i) => console.log(`   ${i + 1}. ${call.desc}\n      to   ${call.to}  value 0\n      data ${call.data}`));
  }
  console.log("\nSafe tx 2 only goes through when the Safe sends it: the proxy runs finalizeUpgrade(),");
  console.log("which is governance-only. On the way in it drops MORPHO from each strategy's reward");
  console.log("tokens (its route through the liquidator has no liquidity, so any sale of it reverts");
  console.log("the hard work); ARB stays. No fee is forgiven and no funds move.");
  console.log("Before signing it, read nextImplementation() on each proxy: upgrade() installs whatever");
  console.log("is scheduled there, and the calldata does not say what that is.");
  console.log("\nUntil Safe tx 2 has run, MORPHO sent to one of these strategies still blocks its vault's");
  console.log("deposits and withdrawals. The stopgap is strategy.salvage(recipient, MORPHO, balance) on");
  console.log("that proxy, from the Safe (not Controller.salvageStrategy), repeated if more arrives.");
  console.log("MORPHO left in a strategy after the upgrade can be taken out the same way.");

  console.log(`\n${rollback.label} (only if needed; then, strictly after 12h, Safe tx 2 again)`);
  rollback.calls.forEach((call, i) => console.log(`   ${i + 1}. ${call.desc}\n      to   ${call.to}  value 0\n      data ${call.data}`));
  console.log("   A rollback brings the old code back, not MORPHO: the reward list stays as the upgrade left it.");

  const out = process.env.OUT || "./safe-transactions";
  console.log(`\n=== Safe Transaction Builder files (chainId ${plan.CHAIN_ID}, Safe ${SAFE}) ===`);
  writeTxBuilderFiles(out, files);
  console.log("   Load each in Transaction Builder and check the decoded calls against the list above.");
  console.log("   Builder may warn about a checksum / 'modified' file on import (these files are");
  console.log("   generated, not exported from Builder): expected.");
  if (hre.network.name === "hardhat") {
    console.log("   DRY RUN on the fork: these implementations are not on Arbitrum. Do not load the files.");
  }

  console.log("\n=== Deployed addresses (record these) ===");
  console.log(JSON.stringify(impls, null, 2));
  console.log("\nTo write the files again without redeploying anything:");
  console.log(`  ${Object.entries(impls).map(([key, impl]) => `${key}_IMPL=${impl}`).join(" ")} VERIFY_REUSED=1 \\`);
  console.log(`    ${only.length ? `ONLY=${only.join(",")} ` : ""}npx hardhat run scripts/12-prepare-morpho-v2-upgrade.js --network mainnet`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
