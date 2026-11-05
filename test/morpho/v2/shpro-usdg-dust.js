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

// Regression cover for a reward sale too small to survive the liquidator. Anyone can send
// the strategy a reward token, and whatever arrives is streamed over 48 hours. A few hundred
// thousand wei of ARB streams at a few wei a second, so each hard work was handed some ten
// thousand wei to sell - which comes out of the swap as no WETH at all, and the swap reverts
// with 'Too little received'. That took the whole hard work down with it, for next to nothing.
describe("Arbitrum Mainnet Morpho Vault V2 Steakhouse USDG Pro dust rewards", function() {
  let accounts;

  // external contracts
  let underlying;

  // external setup
  let underlyingWhale = "0x264bd8291fAE1D75DB2c5F573b07faA6715997B5";
  let arbWhale = "0xf7F468B184A48f6ca37EeFFE12733Ee1c16B6E26";
  let arb = "0x912CE59144191C1204E64559FE8253a0e49E6548";
  let usdg = "0x004B506865409877C9fA29bfb1ebA929984B9bbC";
  let usdc = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
  let weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  let arbToken;

  // parties in the protocol
  let governance;
  let farmer1;

  // numbers used in tests
  let farmerBalance = new BigNumber(100000e6).toFixed();

  // Core protocol contracts
  let controller;
  let vault;
  let strategy;

  async function setupExternalContracts() {
    underlying = await IERC20.at(usdg);
    console.log("Fetching Underlying at: ", underlying.address);
    arbToken = await IERC20.at(arb);
  }

  async function setupBalance(){
    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: underlyingWhale, value: 10e18});
    await web3.eth.sendTransaction({ from: etherGiver, to: arbWhale, value: 10e18});
    await underlying.transfer(farmer1, farmerBalance, { from: underlyingWhale });
  }

  before(async function() {
    governance = addresses.Governance;
    accounts = await web3.eth.getAccounts();

    farmer1 = accounts[1];

    await impersonates([governance, underlyingWhale, arbWhale, addresses.ULOwner]);

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

  describe("Dust rewards", function() {
    it("A dust reward stream cannot block the hard work", async function() {
      // 3 wei a second over the 48 hour stream
      await arbToken.transfer(strategy.address, 172800 * 3, { from: arbWhale });
      await controller.doHardWork(vault.address, { from: governance });
      await Utils.waitHours(1);

      const sellable = new BigNumber(await strategy.sellable(arb));
      const arbBefore = new BigNumber(await arbToken.balanceOf(strategy.address));
      console.log("ARB unlocked after an hour: ", sellable.toFixed());
      Utils.assertBNGt(sellable, 0);

      // this is the hard work that used to revert
      await controller.doHardWork(vault.address, { from: governance });

      // nothing was sold, and nothing was lost either
      Utils.assertBNEq(await arbToken.balanceOf(strategy.address), arbBefore);
    });

    it("A real reward is still sold", async function() {
      await arbToken.transfer(strategy.address, new BigNumber(10e18), { from: arbWhale });
      await controller.doHardWork(vault.address, { from: governance });
      await Utils.advanceNBlock(3600);

      const arbBefore = new BigNumber(await arbToken.balanceOf(strategy.address));
      const sharePriceBefore = new BigNumber(await vault.getPricePerFullShare());
      await controller.doHardWork(vault.address, { from: governance });
      const arbAfter = new BigNumber(await arbToken.balanceOf(strategy.address));
      const sharePriceAfter = new BigNumber(await vault.getPricePerFullShare());

      console.log("ARB sold: ", arbBefore.minus(arbAfter).toFixed());
      Utils.assertBNGt(arbBefore, arbAfter);
      Utils.assertBNGt(sharePriceAfter, sharePriceBefore);

      // once the stream has run out, all that is left is what truncation in the stream
      // rate strands - a wei a second at most - which stays under the sale floor
      await Utils.waitHours(49);
      await controller.doHardWork(vault.address, { from: governance });
      const arbLeft = new BigNumber(await arbToken.balanceOf(strategy.address));
      console.log("ARB left once the stream has run out: ", arbLeft.toFixed());
      Utils.assertBNGte(new BigNumber(172800), arbLeft);
    });
  });
});
