// Utilities
const Utils = require("../../utilities/Utils.js");
const {
  impersonates,
  depositVault,
} = require("../../utilities/hh-utils.js");

const addresses = require("../../test-config.js");
const BigNumber = require("bignumber.js");
const IERC20 = artifacts.require("IERC20");
const IController = artifacts.require("IController");
const Vault = artifacts.require("VaultV2");
const StrategyProxy = artifacts.require("StrategyProxy");

const plan = require("../../../scripts/morpho-v2-upgrade-plan.js");

// Developed and tested at blockNumber 521420000

// Rehearsal of the upgrade of the three live Morpho V2 strategies. It runs the plan from
// scripts/morpho-v2-upgrade-plan.js call for call with the Safe as the sender, which is
// what the Transaction Builder files written by scripts/12-prepare-morpho-v2-upgrade.js
// carry. The steps build on each other and have to run in order.
describe("Arbitrum Mainnet Morpho Vault V2 strategies upgrade rehearsal", function() {
  let accounts;

  // external contracts
  let underlying;
  let morphoToken;
  let arbToken;

  // external setup
  let underlyingWhale = "0xC84CE6998FBABccb2E4a1f34ce19634e800Bc9De";
  let morphoWhale = "0xA3D843B6a057504284006BeF6F34A2E9Bc80Fb6b";
  let morpho = "0x40BD670A58238e6E230c430BBb5cE6ec0d40df48";
  let arbWhale = "0xf7F468B184A48f6ca37EeFFE12733Ee1c16B6E26";
  let arb = "0x912CE59144191C1204E64559FE8253a0e49E6548";

  // parties in the protocol
  let safe = plan.SAFE;
  let farmer1;
  let stranger;

  // Core protocol contracts
  let controller;
  // per strategy: { ...plan entry, Artifact, vault, strategy, proxy, impl }
  let targets = [];
  let thePlan;

  async function assertReverts(promise, reason) {
    try {
      await promise;
    } catch (error) {
      assert.include(error.message, reason || "revert");
      return;
    }
    assert.fail("Expected a revert but the call went through");
  }

  // A plan tx the way the Safe sends it: every inner call, in order, from the Safe.
  async function execute(tx, from = safe) {
    for (const call of tx.calls) {
      await web3.eth.sendTransaction({ from, to: call.to, data: call.data, gas: 5000000 });
    }
  }

  async function readState(target) {
    return {
      morphoVault: await target.strategy.morphoVault(),
      underlying: await target.strategy.underlying(),
      vault: await target.strategy.vault(),
      rewardToken: await target.strategy.rewardToken(),
      strategist: await target.strategy.strategist(),
      storedSupplied: (await target.strategy.storedSupplied()).toString(),
      pendingFee: (await target.strategy.pendingFee()).toString(),
      arbDistributionTime: (await target.strategy.distributionTime(arb)).toString(),
      arbBalance: (await arbToken.balanceOf(target.proxy.address)).toString(),
      sharePrice: (await target.vault.getPricePerFullShare()).toString(),
    };
  }

  before(async function() {
    accounts = await web3.eth.getAccounts();

    farmer1 = accounts[1];
    stranger = accounts[2];

    // impersonate accounts
    await impersonates([safe, underlyingWhale, morphoWhale, arbWhale]);

    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: safe, value: 10e18});
    await web3.eth.sendTransaction({ from: etherGiver, to: underlyingWhale, value: 10e18});
    await web3.eth.sendTransaction({ from: etherGiver, to: morphoWhale, value: 10e18});
    await web3.eth.sendTransaction({ from: etherGiver, to: arbWhale, value: 10e18});

    underlying = await IERC20.at("0xaf88d065e77c8cC2239327C5EDb3A432268e5831");
    morphoToken = await IERC20.at(morpho);
    arbToken = await IERC20.at(arb);
    controller = await IController.at(addresses.Controller);
    await underlying.transfer(farmer1, new BigNumber(30000e6).toFixed(), { from: underlyingWhale });

    // the deployer's part: one new implementation per strategy
    const impls = {};
    for (const entry of plan.STRATEGIES) {
      const Artifact = artifacts.require(entry.artifact);
      const impl = await Artifact.new();
      impls[entry.key] = impl.address;
      targets.push({
        ...entry,
        Artifact,
        impl: impl.address,
        vault: await Vault.at(entry.vault),
        strategy: await Artifact.at(entry.proxy),
        proxy: await StrategyProxy.at(entry.proxy),
      });
    }
    thePlan = plan.upgradePlan(impls);
  });

  describe("Upgrade", function() {
    it("The plan targets what is live", async function() {
      assert.equal(safe, addresses.Governance);
      for (const target of targets) {
        assert.equal(await target.vault.strategy(), target.proxy.address, target.farm);
        assert.equal(await target.proxy.implementation(), target.liveImpl, target.farm);
        assert.equal(await target.strategy.governance(), safe, target.farm);

        // the new implementation is this build, and the live one is not
        const artifact = await hre.artifacts.readArtifact(target.artifact);
        await plan.assertImplMatchesBuild(hre.ethers.provider, artifact, target.impl);
        await assertReverts(plan.assertImplMatchesBuild(hre.ethers.provider, artifact, target.liveImpl), "is not this build's");
      }

      // the Transaction Builder files carry the plan's calls and nothing else
      const impls = Object.fromEntries(targets.map(target => [target.key, target.impl]));
      const files = plan.upgradeFiles(impls);
      assert.equal(files.length, 3);
      for (const { file, description, tx } of files) {
        const json = plan.txBuilderFile(file, description, tx);
        assert.equal(json.chainId, "42161");
        assert.equal(json.meta.createdFromSafeAddress, safe);
        assert.deepEqual(json.transactions.map(t => [t.to, t.data, t.value]), tx.calls.map(call => [call.to, call.data, "0"]));
        assert.deepEqual(json.transactions.map(t => t.to), targets.map(target => target.proxy.address));
      }
    });

    // Anyone can send the strategy MORPHO. It is streamed like any other reward, and once
    // some of it has unlocked the hard work tries to sell it, on a route with no liquidity:
    // the swap router reverts, without a reason. These vaults run the hard work on every
    // deposit and withdrawal too. ARB goes in alongside, so that a stream is under way
    // when the upgrade happens.
    it("MORPHO blocks the live strategies today", async function() {
      for (const target of targets) {
        await depositVault(farmer1, underlying, target.vault, new BigNumber(1000e6).toFixed());
        await morphoToken.transfer(target.proxy.address, new BigNumber(1e15).toFixed(), { from: morphoWhale });
        await arbToken.transfer(target.proxy.address, new BigNumber(10e18).toFixed(), { from: arbWhale });
        // nothing has unlocked yet, so this one still goes through
        await controller.doHardWork(target.vault.address, { from: safe });
      }
      await Utils.waitHours(1);
      for (const target of targets) {
        Utils.assertBNGt(await target.strategy.sellable(morpho), 0);
        await assertReverts(controller.doHardWork(target.vault.address, { from: safe }));
        await assertReverts(depositVault(farmer1, underlying, target.vault, new BigNumber(1000e6).toFixed()));
        await assertReverts(target.vault.withdraw(new BigNumber(await target.vault.balanceOf(farmer1)).toFixed(), { from: farmer1 }));
      }
    });

    it("Safe tx 1 schedules, and nothing can be upgraded early", async function() {
      await execute(thePlan.safeTxs[0]);
      for (const target of targets) {
        assert.equal(await target.strategy.nextImplementation(), target.impl, target.farm);
        assert.equal(await target.proxy.implementation(), target.liveImpl, target.farm);
      }
      await assertReverts(execute(thePlan.safeTxs[1]), "Upgrade not scheduled");
    });

    it("Safe tx 2 upgrades all three with their storage intact", async function() {
      await Utils.waitHours(13);

      const statesBefore = [];
      const arbSellableBefore = [];
      for (const target of targets) {
        statesBefore.push(await readState(target));
        arbSellableBefore.push(new BigNumber(await target.strategy.sellable(arb)));
      }

      // only the Safe can run it
      await assertReverts(execute(thePlan.safeTxs[1], stranger), "Issue when finalizing the upgrade");
      await execute(thePlan.safeTxs[1]);

      for (const [i, target] of targets.entries()) {
        assert.equal(await target.proxy.implementation(), target.impl, target.farm);
        assert.equal(await target.strategy.nextImplementation(), "0x0000000000000000000000000000000000000000", target.farm);
        Utils.assertBNEq(await target.strategy.nextImplementationTimestamp(), 0);

        const stateAfter = await readState(target);
        console.log(target.farm, stateAfter);
        assert.deepEqual(stateAfter, statesBefore[i], target.farm);

        // the ARB stream carried on through the upgrade
        Utils.assertBNGt(arbSellableBefore[i], 0);
        Utils.assertBNGte(new BigNumber(await target.strategy.sellable(arb)), arbSellableBefore[i]);

        // ARB is the only reward left
        assert.equal(await target.strategy.rewardTokens(0), arb, target.farm);
        let secondReward = null;
        try {
          secondReward = await target.strategy.rewardTokens(1);
        } catch (error) {}
        assert.equal(secondReward, null, "MORPHO should be gone from the reward tokens");
      }
    });

    it("Hard work, deposits and withdrawals go through again", async function() {
      for (const target of targets) {
        const morphoBefore = new BigNumber(await morphoToken.balanceOf(target.proxy.address));
        const arbBefore = new BigNumber(await arbToken.balanceOf(target.proxy.address));
        const farmerBefore = new BigNumber(await underlying.balanceOf(farmer1));
        const sharesBefore = new BigNumber(await target.vault.balanceOf(farmer1));

        // the hard work sells the ARB that unlocked while the vault was blocked
        await controller.doHardWork(target.vault.address, { from: safe });
        Utils.assertBNGt(arbBefore, new BigNumber(await arbToken.balanceOf(target.proxy.address)));

        await depositVault(farmer1, underlying, target.vault, new BigNumber(1000e6).toFixed());
        await Utils.advanceNBlock(3600);
        await controller.doHardWork(target.vault.address, { from: safe });
        await target.vault.withdraw(new BigNumber(await target.vault.balanceOf(farmer1)).toFixed(), { from: farmer1 });

        // the deposit from before the upgrade and the one after it both came back with
        // yield on top, and the MORPHO was left where it is
        const farmerAfter = new BigNumber(await underlying.balanceOf(farmer1));
        console.log(target.farm, "farmer gained: ", farmerAfter.minus(farmerBefore).toFixed());
        Utils.assertBNGt(sharesBefore, 0);
        Utils.assertBNGt(farmerAfter, farmerBefore.plus(1000e6));
        Utils.assertBNEq(await morphoToken.balanceOf(target.proxy.address), morphoBefore);

        // which the Safe can take out
        await target.strategy.salvage(safe, morpho, morphoBefore.toFixed(), { from: safe });
        Utils.assertBNEq(await morphoToken.balanceOf(target.proxy.address), 0);
      }
    });

    it("Governance can switch reward sales off", async function() {
      const target = targets[0];
      await assertReverts(target.strategy.setSell(false, { from: stranger }), "Not governance");
      await target.strategy.setSell(false, { from: safe });

      const arbBefore = new BigNumber(await arbToken.balanceOf(target.proxy.address));
      Utils.assertBNGt(arbBefore, 1e12);
      await Utils.waitHours(1);
      await controller.doHardWork(target.vault.address, { from: safe });
      Utils.assertBNEq(await arbToken.balanceOf(target.proxy.address), arbBefore);

      await target.strategy.setSell(true, { from: safe });
      await controller.doHardWork(target.vault.address, { from: safe });
      Utils.assertBNGt(arbBefore, new BigNumber(await arbToken.balanceOf(target.proxy.address)));
    });

    it("The rollback goes back to the live implementations", async function() {
      await execute(thePlan.rollbackSafeTxs[0]);
      await Utils.waitHours(13);
      await execute(thePlan.safeTxs[1]);

      for (const target of targets) {
        assert.equal(await target.proxy.implementation(), target.liveImpl, target.farm);
        // the old code runs again, without MORPHO in its way: the reward list stays as the
        // upgrade left it
        assert.equal(await target.strategy.rewardTokens(0), arb, target.farm);
        await controller.doHardWork(target.vault.address, { from: safe });
      }
    });
  });
});
