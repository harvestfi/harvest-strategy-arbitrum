// The governance plan for upgrading the three LIVE Morpho Vault V2 strategies on Arbitrum,
// shared by scripts/12-prepare-morpho-v2-upgrade.js (prints it and writes the Transaction
// Builder files) and test/morpho/v2/upgrade-rehearsal.js (executes it on a fork with the
// Safe as the sender). Keeping one source means the calldata that is handed to governance
// is exactly the calldata that was rehearsed.
//
// No hardhat import: plain ethers v5, so it can be required from scripts and tests alike.

const { ethers } = require("ethers");

// Gnosis Safe 1.3.0 (threshold 2): governance of the strategies, their vaults and the Controller.
const SAFE = "0xF066789028fE31D4f53B69B81b328B8218Cc0641";
const CHAIN_ID = "42161";
// Transaction Builder version stamped into the JSON files.
const TX_BUILDER_VERSION = "1.18.3";

// The strategies behind the three Morpho V2 farms. `liveImpl` is what each proxy runs today,
// and what a rollback schedules again.
const STRATEGIES = [
  {
    key: "GC",
    farm: "Gauntlet Balanced V2",
    artifact: "MorphoVaultStrategyMainnet_GC_USDC_V2",
    vault: "0x34E2110F8C9a635477EFf75FDBe73251Fe02ae4a",
    proxy: "0x74BB57F88deC230e5586CB9ca1e7A55ac1122a9c",
    liveImpl: "0x3C9d520Aa82F20F090F3880cb2498135c87Aa0a2",
  },
  {
    key: "GP",
    farm: "Gauntlet Prime V2",
    artifact: "MorphoVaultStrategyMainnet_GP_USDC_V2",
    vault: "0xE6e61bF3Ec29b4ab1846EA2851FA021C0BE886BA",
    proxy: "0x80875EA382f56503710A702f32F4d6350cbA36bF",
    liveImpl: "0x3B91761c1D59b93A13a65f09F55C37040d912C7B",
  },
  {
    key: "SHHY",
    farm: "Steakhouse High Yield V2",
    artifact: "MorphoVaultStrategyMainnet_SHHY_USDC_V2",
    vault: "0xedE9330Aa169f0fEca59E2e62fF443682862a0a4",
    proxy: "0xb7c6d55f829A41C8F54b319eE2b8fB2425f6bB2C",
    liveImpl: "0x1cE36b49eDF370EF4F865B1A3c2f1FD22b47DD28",
  },
];

const iface = new ethers.utils.Interface([
  "function scheduleUpgrade(address impl)",
  "function upgrade()",
]);

// One inner call: target, human-readable description, calldata.
const c = (to, desc, fn, args = []) => ({ to, desc, data: iface.encodeFunctionData(fn, args) });

// The strategies named in `impls` ({ GC: "0x…", GP: "0x…", SHHY: "0x…" }), each with its
// new implementation. A key can be left out to keep that strategy as it is.
function selected(impls) {
  const unknown = Object.keys(impls).filter((key) => !STRATEGIES.some((s) => s.key === key));
  if (unknown.length) throw new Error(`unknown strategy key: ${unknown.join(", ")}`);
  const picked = STRATEGIES.filter((s) => impls[s.key]).map((s) => {
    const impl = ethers.utils.getAddress(impls[s.key]); // throws on a malformed address
    if (impl === ethers.constants.AddressZero) throw new Error(`${s.key}: the implementation is the zero address`);
    if (impl === ethers.utils.getAddress(s.liveImpl)) throw new Error(`${s.key}: ${impl} is the implementation it already runs`);
    return { ...s, impl };
  });
  if (!picked.length) throw new Error("no implementation given");
  return picked;
}

/**
 * The rollout for the given new implementations.
 *  - safeTxs[0]: schedules every upgrade; starts the 12h timelock.
 *  - safeTxs[1]: StrategyProxy.upgrade() on every strategy, strictly after the timelock.
 *    It has to come from the Safe: the proxy delegatecalls finalizeUpgrade(), which is
 *    governance-only. Its calldata does not depend on the implementation, so the same
 *    batch also completes a rollback.
 *  - rollbackSafeTxs[0]: schedules the live implementations again (then safeTxs[1] after 12h).
 * Each tx lists its inner calls; `calls` is what goes into Transaction Builder.
 */
function upgradePlan(impls) {
  const picked = selected(impls);
  const safeTxs = [
    {
      label: "Safe tx 1 (schedule the upgrades; starts the 12h timelock)",
      calls: picked.map((s) => c(s.proxy, `${s.farm}: strategy.scheduleUpgrade(${s.impl})`, "scheduleUpgrade", [s.impl])),
    },
    {
      label: "Safe tx 2 (strictly after the 12h)",
      calls: picked.map((s) => c(s.proxy, `${s.farm}: StrategyProxy.upgrade()  [runs finalizeUpgrade() as the Safe]`, "upgrade")),
    },
  ];
  const rollbackSafeTxs = [
    {
      label: "Rollback: schedule the live implementations again",
      calls: picked.map((s) => c(s.proxy, `${s.farm}: strategy.scheduleUpgrade(${s.liveImpl})`, "scheduleUpgrade", [s.liveImpl])),
    },
  ];
  return { strategies: picked, safeTxs, rollbackSafeTxs };
}

/**
 * The Transaction Builder files of the rollout: [{ file, description, tx }], in execution
 * order, tx from upgradePlan(). The script writes exactly these files and the rehearsal
 * executes exactly these txs.
 */
function upgradeFiles(impls) {
  const { strategies, safeTxs: [tx1, tx2], rollbackSafeTxs: [rollback] } = upgradePlan(impls);
  const farms = strategies.map((s) => s.farm).join(", ");
  return [
    { file: "morpho-v2-upgrade-1-schedule.json",
      description: `Morpho V2 strategies (${farms}): scheduleUpgrade on each; starts the 12h timelock`, tx: tx1 },
    { file: "morpho-v2-upgrade-2-upgrade.json",
      description: `Morpho V2 strategies (${farms}): upgrade() on each, strictly after nextImplementationTimestamp`, tx: tx2 },
    { file: "morpho-v2-upgrade-rollback-schedule.json",
      description: `Morpho V2 strategies (${farms}) rollback: scheduleUpgrade back to the live implementations`, tx: rollback },
  ];
}

/**
 * Safe Transaction Builder JSON for one plan tx. It lists the raw inner calls; Builder
 * itself wraps a batch of them in a delegatecall to MultiSendCallOnly, which leaves the
 * Safe as the sender of every one.
 */
function txBuilderFile(name, description, tx) {
  return {
    version: "1.0",
    chainId: CHAIN_ID,
    createdAt: Date.now(),
    meta: { name, description, txBuilderVersion: TX_BUILDER_VERSION, createdFromSafeAddress: SAFE },
    transactions: tx.calls.map((call) => ({
      to: call.to, value: "0", data: call.data, contractMethod: null, contractInputsValues: null,
    })),
  };
}

/**
 * Throws unless `impl` holds exactly this build's strategy. The strategies have no
 * immutables and link no libraries, so the runtime code has to match byte for byte.
 */
async function assertImplMatchesBuild(provider, artifact, impl) {
  const onchain = (await provider.getCode(impl)).toLowerCase();
  if (onchain === "0x") throw new Error(`strategy impl ${impl} has no code`);
  if (onchain !== artifact.deployedBytecode.toLowerCase()) {
    throw new Error(`strategy impl ${impl} is not this build's ${artifact.contractName} `
      + "(different source or compiler settings)");
  }
}

module.exports = {
  SAFE, CHAIN_ID, STRATEGIES, upgradePlan, upgradeFiles, txBuilderFile, assertImplMatchesBuild,
};
