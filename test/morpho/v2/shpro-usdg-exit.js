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

const Strategy = artifacts.require("MorphoVaultStrategyMainnet_SHPRO_USDG_V2");

// Developed and tested at blockNumber 521420000

// Regression cover for the exit path: `withdrawAllToVault()` used to hand the vault every
// last unit of underlying, including the amount backing a `pendingFee` that `_handleFee`
// had left unpaid because it sat under `feeFloor()`. `investedUnderlyingBalance()` is
// `idle + stored - pendingFee`, so the strategy was then left reporting a negative balance
// and every vault entrypoint that reads it reverted.
//
// The deposit here is deliberately small and the wait short, so the fee accrued between
// harvests lands under the floor and stays pending - that is the branch being covered.
describe("Arbitrum Mainnet Morpho Vault V2 Steakhouse USDG Pro exit paths", function() {
  let accounts;

  // external contracts
  let underlying;
  let wethToken;

  // external setup
  let underlyingWhale = "0x264bd8291fAE1D75DB2c5F573b07faA6715997B5";
  let usdg = "0x004B506865409877C9fA29bfb1ebA929984B9bbC";
  let usdc = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
  let weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";

  // parties in the protocol
  let governance;
  let farmer1;

  // numbers used in tests - small on purpose, see the note above
  let farmerBalance = new BigNumber(200e6).toFixed();

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
    await underlying.transfer(farmer1, farmerBalance, { from: underlyingWhale });
  }

  before(async function() {
    governance = addresses.Governance;
    accounts = await web3.eth.getAccounts();

    farmer1 = accounts[1];

    await impersonates([governance, underlyingWhale, addresses.ULOwner]);

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

    await setupBalance();

    await depositVault(farmer1, underlying, vault, farmerBalance);
    await controller.doHardWork(vault.address, { from: governance });
  });

  describe("Exit paths", function() {
    it("Keeps an unpayable fee behind instead of bricking the vault", async function() {
      // a short wait on a small position leaves a fee under the floor, so it stays pending
      await Utils.waitHours(1);

      await strategy.withdrawAllToVault({ from: governance });

      const pendingFee = new BigNumber(await strategy.pendingFee());
      const idle = new BigNumber(await underlying.balanceOf(strategy.address));
      const invested = new BigNumber(await strategy.investedUnderlyingBalance());
      console.log("pending fee kept in the strategy: ", pendingFee.toFixed());
      console.log("idle underlying in the strategy:  ", idle.toFixed());
      console.log("investedUnderlyingBalance:        ", invested.toFixed());

      // the fee is genuinely unpaid and under the floor - this is the branch under test
      Utils.assertBNGt(pendingFee, 0);
      Utils.assertBNGte(new BigNumber(await strategy.feeFloor()), pendingFee);
      // and it is still backed by underlying the strategy actually holds
      Utils.assertBNGte(idle, pendingFee);

      // the vault is readable and usable, which is what used to break
      const sharePrice = new BigNumber(await vault.getPricePerFullShare());
      console.log("share price after the exit: ", sharePrice.toFixed());
      Utils.assertBNGt(sharePrice, 0);

      // the farmer gets the deposit back plus their share of the hour's yield, and the
      // fee left behind is not taken out of their principal
      const farmerBefore = new BigNumber(await underlying.balanceOf(farmer1));
      await vault.withdraw(new BigNumber(await vault.balanceOf(farmer1)).toFixed(), { from: farmer1 });
      const farmerAfter = new BigNumber(await underlying.balanceOf(farmer1));
      const withdrawn = farmerAfter.minus(farmerBefore);
      console.log("farmer withdrew: ", withdrawn.toFixed(), " deposited: ", farmerBalance);
      Utils.assertBNGte(withdrawn, new BigNumber(farmerBalance));
      // the gain is the hour of yield net of the fee, not a raid on the fee kept behind
      assert.equal(
        withdrawn.minus(farmerBalance).lte(1e4),
        true,
        "farmer should not withdraw more than the deposit plus the hour's yield"
      );
      // what was kept back for the fee is still there
      Utils.assertBNGte(new BigNumber(await underlying.balanceOf(strategy.address)), pendingFee);
    });

    // `emergencyExit()` leaves just the fee supplied, and after rounding that position can be
    // worth a unit less than the fee. The next hard work used to ask the Morpho vault for the
    // whole fee regardless, which it cannot pay out of a position that small. The fee is now
    // paid out of what the exit left idle.
    it("Pays the fee out of idle funds after an emergency exit", async function() {
      // a real position this time, held long enough for the fee to clear the floor
      const amount = new BigNumber(50000e6).toFixed();
      await underlying.transfer(farmer1, amount, { from: underlyingWhale });
      const farmerBefore = new BigNumber(await underlying.balanceOf(farmer1));
      await depositVault(farmer1, underlying, vault, amount);
      await controller.doHardWork(vault.address, { from: governance });
      await Utils.advanceNBlock(3600);

      await strategy.emergencyExit({ from: governance });

      const pendingFee = new BigNumber(await strategy.pendingFee());
      const supplied = new BigNumber(await strategy.currentSupplied());
      const idle = new BigNumber(await underlying.balanceOf(strategy.address));
      console.log("pending fee after the exit: ", pendingFee.toFixed());
      console.log("left supplied:              ", supplied.toFixed());
      console.log("idle in the strategy:       ", idle.toFixed());
      Utils.assertBNGt(pendingFee, await strategy.feeFloor());
      Utils.assertBNGte(pendingFee.plus(1), supplied);
      Utils.assertBNGt(idle, pendingFee);

      const platformBefore = new BigNumber(await wethToken.balanceOf(addresses.CommunityMsig));
      const tx = await controller.doHardWork(vault.address, { from: governance });
      const platformAfter = new BigNumber(await wethToken.balanceOf(addresses.CommunityMsig));
      console.log("platform fee WETH gained: ", platformAfter.minus(platformBefore).toFixed());
      Utils.assertBNGt(platformAfter, platformBefore);

      // nothing was asked of the Morpho vault to get there
      const morphoVault = (await strategy.morphoVault()).toLowerCase();
      const withdrawTopic = web3.utils.keccak256("Withdraw(address,address,address,uint256,uint256)");
      const withdrawals = tx.receipt.rawLogs.filter(
        log => log.address.toLowerCase() == morphoVault && log.topics[0] == withdrawTopic
      );
      assert.equal(withdrawals.length, 0, "the fee should not have been redeemed from the Morpho vault");
      Utils.assertBNGte(new BigNumber(await strategy.feeFloor()), new BigNumber(await strategy.pendingFee()));

      // and the way out still works afterwards
      await strategy.withdrawAllToVault({ from: governance });
      await vault.withdraw(new BigNumber(await vault.balanceOf(farmer1)).toFixed(), { from: farmer1 });
      const farmerAfter = new BigNumber(await underlying.balanceOf(farmer1));
      console.log("farmer started with: ", farmerBefore.toFixed(), " ended with: ", farmerAfter.toFixed());
      Utils.assertBNGt(farmerAfter, farmerBefore);
    });
  });
});
