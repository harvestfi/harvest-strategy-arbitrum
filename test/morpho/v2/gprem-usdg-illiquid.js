// Utilities
const Utils = require("../../utilities/Utils.js");
const {
  impersonates,
  setupCoreProtocol,
  depositVault,
} = require("../../utilities/hh-utils.js");

const addresses = require("../../test-config.js");
const BigNumber = require("bignumber.js");
const IERC20 = artifacts.require("IERC20");
const IMorphoVault = artifacts.require("IMorphoVault");
const IMorphoVaultV2 = artifacts.require("IMorphoVaultV2");

const Strategy = artifacts.require("MorphoVaultStrategyMainnet_GPREM_USDG_V2");

// Developed and tested at blockNumber 521420000

// Gauntlet USDG Premium runs without a liquidity adapter most of the time, so a withdrawal
// is paid out of whatever happens to sit idle in the Morpho vault - and its allocator sweeps
// that into the market every few hours. With nothing idle the vault cannot pay out a single
// unit. This covers what the strategy does then:
// - a hard work used to revert on redeeming the fee; the fee now waits instead
// - a withdrawal still cannot be paid, which is correct
// - governance can deallocate and withdraw in one call, for the Morpho vault's penalty
// - once the whole position has been pulled that way, nothing is left behind for a later
//   exit to trip over
// The steps build on each other and have to run in order.
describe("Arbitrum Mainnet Morpho Vault V2 Gauntlet USDG Premium without liquidity", function() {
  let accounts;

  // external contracts
  let underlying;
  let wethToken;
  let morphoVault;

  // external setup
  let underlyingWhale = "0x264bd8291fAE1D75DB2c5F573b07faA6715997B5";
  let usdg = "0x004B506865409877C9fA29bfb1ebA929984B9bbC";
  let usdc = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
  let weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  // the Morpho vault's own allocator, its only adapter and the one market behind it
  let allocator = "0xA33486eaE870526BBf9Ee73aCe2f5179e4a41303";
  let adapter = "0x9f85B18CfDFf5A6f8e85a26d2677Eb44e3F1C941";
  let marketData = web3.eth.abi.encodeParameters(
    ["address", "address", "address", "address", "uint256"],
    [
      usdg,
      "0xE1B0dC5A21b10f1634fBfbE9976fBA2Ee2e1c762", // syrupUSDG collateral
      "0xA722399257215e716C8Aa084D06E4882580934ee", // oracle
      "0x66F30587FB8D4206918deb78ecA7d5eBbafD06DA", // irm
      "915000000000000000",
    ]
  );

  // parties in the protocol
  let governance;
  let farmer1;

  // TransferReverted(): what the Morpho vault throws when it does not hold what it has to pay
  let transferReverted = "0xace2a47e";

  // numbers used in tests
  let farmerBalance = new BigNumber(100000e6).toFixed();
  let maxUint = new BigNumber(2).pow(256).minus(1).toFixed();

  // Core protocol contracts
  let controller;
  let vault;
  let strategy;

  async function setupExternalContracts() {
    underlying = await IERC20.at(usdg);
    console.log("Fetching Underlying at: ", underlying.address);
    wethToken = await IERC20.at(weth);
  }

  async function setupBalance(){
    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: underlyingWhale, value: 10e18});
    await web3.eth.sendTransaction({ from: etherGiver, to: allocator, value: 10e18});
    await underlying.transfer(farmer1, farmerBalance, { from: underlyingWhale });
  }

  async function assertReverts(promise, reason) {
    try {
      await promise;
    } catch (error) {
      assert.include(error.message, reason || "revert");
      return;
    }
    assert.fail("Expected a revert but the call went through");
  }

  // What the allocator does on chain every few hours: put everything idle into the market.
  async function sweepIdle() {
    const idle = new BigNumber(await underlying.balanceOf(morphoVault.address));
    await web3.eth.sendTransaction({
      from: allocator,
      to: morphoVault.address,
      data: web3.eth.abi.encodeFunctionCall({
        name: "allocate",
        type: "function",
        inputs: [
          {type: "address", name: "adapter"},
          {type: "bytes", name: "data"},
          {type: "uint256", name: "assets"},
        ],
      }, [adapter, marketData, idle.toFixed()]),
    });
    Utils.assertBNEq(await underlying.balanceOf(morphoVault.address), 0);
  }

  before(async function() {
    governance = addresses.Governance;
    accounts = await web3.eth.getAccounts();

    farmer1 = accounts[1];

    await impersonates([governance, underlyingWhale, allocator, addresses.ULOwner]);

    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: governance, value: 10e18});
    await web3.eth.sendTransaction({ from: etherGiver, to: addresses.ULOwner, value: 10e18});

    await setupExternalContracts();
    [controller, vault, strategy] = await setupCoreProtocol({
      "existingVaultAddress": null,
      "strategyArtifact": Strategy,
      "strategyArtifactIsUpgradable": true,
      "underlying": underlying,
      "governance": governance,
      "liquidation": [
        {"uniV3": [usdg, usdc, weth]},
        {"uniV3": [weth, usdc, usdg]},
      ],
      "uniV3Fee": [
        [usdg, usdc, 500],
        [usdc, weth, 500],
      ],
      "ULOwner": addresses.ULOwner,
    });
    morphoVault = await IMorphoVault.at(await strategy.morphoVault());

    await setupBalance();

    await depositVault(farmer1, underlying, vault, farmerBalance);
    await controller.doHardWork(vault.address, { from: governance });
  });

  describe("Morpho vault with nothing idle", function() {
    it("Hard work goes through and the fee waits", async function() {
      // half a day of yield, so the fee is well over the floor
      await Utils.advanceNBlock(3600);
      await sweepIdle();

      // the Morpho vault cannot pay the strategy anything at all now
      await impersonates([strategy.address]);
      await web3.eth.sendTransaction({ from: accounts[9], to: strategy.address, value: 1e18});
      await assertReverts(
        morphoVault.withdraw(1e6, strategy.address, strategy.address, { from: strategy.address }),
        transferReverted
      );

      // A few hundred units landing in the strategy do not change that: a part payment
      // has to clear the floor just as the whole fee does, or it would be swapped as dust.
      await underlying.transfer(strategy.address, 500, { from: underlyingWhale });

      const sharePriceBefore = new BigNumber(await vault.getPricePerFullShare());
      const platformBefore = new BigNumber(await wethToken.balanceOf(addresses.CommunityMsig));
      await controller.doHardWork(vault.address, { from: governance });
      const sharePriceAfter = new BigNumber(await vault.getPricePerFullShare());
      const platformAfter = new BigNumber(await wethToken.balanceOf(addresses.CommunityMsig));

      const pendingFee = new BigNumber(await strategy.pendingFee());
      console.log("pending fee carried over: ", pendingFee.toFixed());
      console.log("share price before/after: ", sharePriceBefore.toFixed(), sharePriceAfter.toFixed());
      Utils.assertBNGt(pendingFee, await strategy.feeFloor());
      Utils.assertBNGte(sharePriceAfter, sharePriceBefore);
      // nothing was settled, so nothing reached the platform
      Utils.assertBNEq(platformAfter, platformBefore);

      // the 500 units went into the Morpho vault with the hard work; the allocator takes them
      await sweepIdle();
    });

    it("A withdrawal cannot be paid until governance deallocates", async function() {
      const tenth = new BigNumber(await vault.balanceOf(farmer1)).dividedToIntegerBy(10).toFixed();
      await assertReverts(vault.withdraw(tenth, { from: farmer1 }), transferReverted);

      const amount = new BigNumber(20000e6);
      // the Morpho vault charges this share of what is deallocated, rounded up
      const penaltyRate = new BigNumber(await (await IMorphoVaultV2.at(morphoVault.address)).forceDeallocatePenalty(adapter));
      const expectedPenalty = amount.times(penaltyRate).div(1e18).integerValue(BigNumber.ROUND_CEIL);
      console.log("penalty rate: ", penaltyRate.toFixed(), " expected penalty: ", expectedPenalty.toFixed());
      Utils.assertBNGt(expectedPenalty, 0);

      await assertReverts(
        strategy.forceWithdrawToVault([adapter], [marketData], [amount.toFixed()], amount.toFixed(), maxUint, { from: farmer1 }),
        "Not governance"
      );
      await assertReverts(
        strategy.forceWithdrawToVault([adapter], [marketData], [amount.toFixed()], amount.toFixed(), expectedPenalty.minus(2).toFixed(), { from: governance }),
        "Penalty too high"
      );
      await assertReverts(
        strategy.forceWithdrawToVault([adapter], [marketData, marketData], [amount.toFixed()], amount.toFixed(), maxUint, { from: governance }),
        "Length mismatch"
      );

      const vaultBefore = new BigNumber(await underlying.balanceOf(vault.address));
      const pendingFeeBefore = new BigNumber(await strategy.pendingFee());
      const totalBefore = new BigNumber(await vault.underlyingBalanceWithInvestment());

      const tx = await strategy.forceWithdrawToVault(
        [adapter], [marketData], [amount.toFixed()], amount.toFixed(), expectedPenalty.plus(2).toFixed(), { from: governance }
      );
      const forced = tx.logs.find(log => log.event === "ForcedWithdrawal");
      const paid = new BigNumber(forced.args.penalty);

      const vaultAfter = new BigNumber(await underlying.balanceOf(vault.address));
      const totalAfter = new BigNumber(await vault.underlyingBalanceWithInvestment());
      console.log("vault received: ", vaultAfter.minus(vaultBefore).toFixed());
      console.log("penalty paid:   ", paid.toFixed());

      // the vault got exactly what was asked for, and the position paid the penalty on top
      Utils.assertBNEq(vaultAfter.minus(vaultBefore), amount);
      Utils.assertBNEq(forced.args.withdrawn, amount);
      Utils.assertBNGte(paid, expectedPenalty.minus(2));
      Utils.assertBNGte(expectedPenalty.plus(2), paid);
      // the fee is still owed, and the books match what the position holds
      Utils.assertBNGte(await strategy.pendingFee(), pendingFeeBefore);
      Utils.assertBNEq(await strategy.storedSupplied(), await strategy.currentSupplied());
      // all the vault as a whole lost is the penalty
      Utils.assertBNGte(totalAfter.plus(expectedPenalty).plus(2), totalBefore);

      // and the farmer can be paid out of what was pulled
      const farmerBefore = new BigNumber(await underlying.balanceOf(farmer1));
      await vault.withdraw(tenth, { from: farmer1 });
      Utils.assertBNGt(await underlying.balanceOf(farmer1), farmerBefore);
    });

    it("Governance can pull the whole position", async function() {
      // keep the vault from handing it all straight back at the next hard work
      await vault.setVaultFractionToInvest(0, 100, { from: governance });

      // two entries, between them a little more than the position, and no limit on the amount
      const half = new BigNumber(45000e6).toFixed();
      await strategy.forceWithdrawToVault(
        [adapter, adapter], [marketData, marketData], [half, half], maxUint, new BigNumber(2e6).toFixed(), { from: governance }
      );

      const supplied = new BigNumber(await strategy.currentSupplied());
      const pendingFee = new BigNumber(await strategy.pendingFee());
      const idle = new BigNumber(await underlying.balanceOf(strategy.address));
      console.log("left supplied: ", supplied.toFixed(), " pending fee: ", pendingFee.toFixed(), " idle: ", idle.toFixed());
      // nothing is left in the Morpho vault: the fee came out too and waits in the strategy
      Utils.assertBNGte(new BigNumber(2), supplied);
      Utils.assertBNGt(pendingFee, await strategy.feeFloor());
      Utils.assertBNEq(idle, pendingFee);
      Utils.assertBNGte(new BigNumber(2), new BigNumber(await strategy.investedUnderlyingBalance()));
    });

    it("The way out stays open after the allocator sweeps again", async function() {
      // the last pull freed more than it withdrew; the allocator puts that back to work
      await sweepIdle();
      await Utils.advanceNBlock(7200);

      // the fee settles out of what was kept in the strategy, with nothing from the Morpho vault
      const platformBefore = new BigNumber(await wethToken.balanceOf(addresses.CommunityMsig));
      await controller.doHardWork(vault.address, { from: governance });
      const platformAfter = new BigNumber(await wethToken.balanceOf(addresses.CommunityMsig));
      console.log("platform fee WETH gained: ", platformAfter.minus(platformBefore).toFixed());
      Utils.assertBNGt(platformAfter, platformBefore);
      Utils.assertBNGte(new BigNumber(await strategy.feeFloor()), new BigNumber(await strategy.pendingFee()));
      // and nothing went back in
      Utils.assertBNGte(new BigNumber(2), new BigNumber(await strategy.currentSupplied()));

      // the last holder leaves with everything while the Morpho vault cannot pay a single
      // unit. A unit of rounding dust went back in with the hard work, and the exit goes
      // through without it.
      await sweepIdle();
      console.log("left supplied before the exit: ", (await strategy.currentSupplied()).toString());
      await vault.withdraw(new BigNumber(await vault.balanceOf(farmer1)).toFixed(), { from: farmer1 });
      const farmerNewBalance = new BigNumber(await underlying.balanceOf(farmer1));
      console.log("farmer ends with: ", farmerNewBalance.toFixed(), " started with: ", farmerBalance);
      // half a day of yield more than covers the penalties
      Utils.assertBNGt(farmerNewBalance, farmerBalance);

      // and so would a switch to another strategy
      await strategy.withdrawAllToVault({ from: governance });
    });
  });
});
