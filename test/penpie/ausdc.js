// Utilities
const Utils = require("../utilities/Utils.js");
const {
  impersonates,
  setupCoreProtocol,
  depositVault,
} = require("../utilities/hh-utils.js");

const addresses = require("../test-config.js");
const BigNumber = require("bignumber.js");
const IERC20 = artifacts.require("IERC20");

const Strategy = artifacts.require("PenpieStrategyMainnet_aUSDC");

// Developed and tested at blockNumber 197528200

// Vanilla Mocha test. Increased compatibility with tools that integrate Mocha.
describe("Arbitrum Mainnet Penpie aUSDC", function () {
  let accounts;

  // external contracts
  let underlying;

  // external setup
  let underlyingWhale = "0x7FE4b2632f5AE6d930677D662AF26Bc0a06672b3";
  let pendle = "0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8";
  let weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  let usdc = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";

  // parties in the protocol
  let governance;
  let farmer1;

  // numbers used in tests
  let farmerBalance;

  // Core protocol contracts
  let controller;
  let vault;
  let strategy;

  async function setupExternalContracts() {
    underlying = await IERC20.at("0xBa4A858d664Ddb052158168DB04AFA3cFF5CFCC8");
    console.log("Fetching Underlying at: ", underlying.address);
  }

  async function setupBalance() {
    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: underlyingWhale, value: 10e18 });

    farmerBalance = await underlying.balanceOf(underlyingWhale);
    await underlying.transfer(farmer1, farmerBalance, { from: underlyingWhale });
  }

  before(async function () {
    governance = addresses.Governance;
    accounts = await web3.eth.getAccounts();

    farmer1 = accounts[1];

    // impersonate accounts
    await impersonates([governance, underlyingWhale, addresses.ULOwner]);

    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: governance, value: 10e18 });
    await web3.eth.sendTransaction({ from: etherGiver, to: addresses.ULOwner, value: 10e18 });

    await setupExternalContracts();
    [controller, vault, strategy] = await setupCoreProtocol({
      "existingVaultAddress": null,
      "strategyArtifact": Strategy,
      "strategyArtifactIsUpgradable": true,
      "underlying": underlying,
      "governance": governance,
      "liquidation": [
        { "uniV3": [pendle, weth] },
        { "uniV3": [usdc, weth] },
        { "uniV3": [weth, usdc] },
      ],
      "ULOwner": addresses.ULOwner
    });

    // whale send underlying to farmers
    await setupBalance();
  });

  describe("Happy path", function () {
    it("Farmer should earn money", async function () {
      let farmerOldBalance = new BigNumber(await underlying.balanceOf(farmer1));
      await depositVault(farmer1, underlying, vault, farmerBalance);

      let hours = 10;
      // let blocksPerHour = 3600 * 4 * 24;
      let blocksPerHour = 3600 * 4;
      let oldSharePrice;
      let newSharePrice;

      for (let i = 0; i < hours; i++) {
        console.log("loop ", i);

        oldSharePrice = new BigNumber(await vault.getPricePerFullShare());
        await controller.doHardWork(vault.address, { from: governance });
        newSharePrice = new BigNumber(await vault.getPricePerFullShare());

        console.log("old shareprice: ", oldSharePrice.toFixed());
        console.log("new shareprice: ", newSharePrice.toFixed());
        console.log("growth: ", newSharePrice.toFixed() / oldSharePrice.toFixed());

        apr = (newSharePrice.toFixed() / oldSharePrice.toFixed() - 1) * (24 / (blocksPerHour / 300)) * 365;
        apy = ((newSharePrice.toFixed() / oldSharePrice.toFixed() - 1) * (24 / (blocksPerHour / 300)) + 1) ** 365;

        console.log("instant APR:", apr * 100, "%");
        console.log("instant APY:", (apy - 1) * 100, "%");

        await Utils.advanceNBlock(blocksPerHour);
      }
      await vault.withdraw(new BigNumber(await vault.balanceOf(farmer1)).toFixed(), { from: farmer1 });
      let farmerNewBalance = new BigNumber(await underlying.balanceOf(farmer1));
      Utils.assertBNGt(farmerNewBalance, farmerOldBalance);

      apr = (farmerNewBalance.toFixed() / farmerOldBalance.toFixed() - 1) * (24 / (blocksPerHour * hours / 300)) * 365;
      apy = ((farmerNewBalance.toFixed() / farmerOldBalance.toFixed() - 1) * (24 / (blocksPerHour * hours / 300)) + 1) ** 365;

      console.log("earned!");
      console.log("APR:", apr * 100, "%");
      console.log("APY:", (apy - 1) * 100, "%");

      await strategy.withdrawAllToVault({ from: governance }); // making sure can withdraw all for a next switch

    });
  });
});
