// Utilities
const Utils = require("../utilities/Utils.js");
const {
  impersonates,
  setupCoreProtocol,
  depositVault,
} = require("../utilities/hh-utils.js");

const addresses = require("../test-config.js");
const { send } = require("@openzeppelin/test-helpers");
const BigNumber = require("bignumber.js");
const IERC20 = artifacts.require("IERC20");

//const Strategy = artifacts.require("");
const Strategy = artifacts.require("XGrailStrategyMainnet_XGrail");
const IXGrail = artifacts.require("IXGrail")

// Developed and tested at blockNumber 93059350

// Vanilla Mocha test. Increased compatibility with tools that integrate Mocha.
describe("Arbitrum Mainnet Camelot xGRAIL", function() {
  let accounts;

  // external contracts
  let underlying;

  // external setup
  let underlyingWhale = "0x5E29fC164189ae03f7F05ab4a6E14620Df60501c";
  let camelotGovernance = "0x460d0F7B75412592D14440857f715ec28861c2D7";
  let weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  let usdc = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
  let grail = "0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8";

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
    underlying = await IERC20.at("0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b");
    console.log("Fetching Underlying at: ", underlying.address);
  }

  async function setupBalance(){
    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: underlyingWhale, value: 10e18});

    farmerBalance = await underlying.balanceOf(underlyingWhale);
    await underlying.transfer(farmer1, farmerBalance, { from: underlyingWhale });
  }

  before(async function() {
    governance = addresses.Governance;
    accounts = await web3.eth.getAccounts();

    farmer1 = accounts[1];

    // impersonate accounts
    await impersonates([governance, underlyingWhale, camelotGovernance]);

    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: governance, value: 10e18});
    await web3.eth.sendTransaction({ from: etherGiver, to: camelotGovernance, value: 10e18});

    await setupExternalContracts();
    [controller, vault, strategy] = await setupCoreProtocol({
      "existingVaultAddress": null,
      "strategyArtifact": Strategy,
      "strategyArtifactIsUpgradable": true,
      "underlying": underlying,
      "governance": governance,
      "liquidation": [{"camelot": [usdc, grail]}, {"camelot": [grail, usdc]}, {"camelot": [weth, usdc, grail]}, {"camelot": [grail, usdc, weth]}]
    });

    xGrail = await IXGrail.at("0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b");
    await xGrail.updateTransferWhitelist(vault.address, true, {from: camelotGovernance});
    await xGrail.updateTransferWhitelist(underlyingWhale, true, {from: camelotGovernance});

    await controller.setUniversalLiquidator(addresses.UniversalLiquidator, {from: governance});
    await controller.setRewardForwarder(addresses.RewardForwarder, {from: governance});

    // whale send underlying to farmers
    await setupBalance();
  });

  describe("Happy path", function() {
    it("Farmer should earn money", async function() {
      let farmerOldBalance = new BigNumber(await underlying.balanceOf(farmer1));
      console.log(farmerOldBalance.toFixed())
      await depositVault(farmer1, underlying, vault, farmerBalance);
      console.log(await strategy.controller())
      console.log(await strategy.governance())

      let hours = 10;
      let blocksPerHour = 3600;
      let oldSharePrice;
      let newSharePrice;

      for (let i = 0; i < hours; i++) {
        console.log("loop ", i);

        if (i == 5) {
          strategy.setAllocationTargets(
            ["0x5422AA06a38fd9875fc2501380b40659fEebD3bB", "0xD27c373950E7466C53e5Cd6eE3F70b240dC0B1B1"],
            [7500, 2500],
            ["0x0000000000000000000000000000000000000000", "0x5DbFE78Bf6d6FDE1db1854c9A30DFb2d565e6152"],
            [0, 1],
            {from: governance}
          )
        }

        oldSharePrice = new BigNumber(await vault.getPricePerFullShare());
        await controller.doHardWork(vault.address, { from: governance });
        newSharePrice = new BigNumber(await vault.getPricePerFullShare());

        console.log("old shareprice: ", oldSharePrice.toFixed());
        console.log("new shareprice: ", newSharePrice.toFixed());
        console.log("growth: ", newSharePrice.toFixed() / oldSharePrice.toFixed());

        apr = (newSharePrice.toFixed()/oldSharePrice.toFixed()-1)*(24/(blocksPerHour/300))*365;
        apy = ((newSharePrice.toFixed()/oldSharePrice.toFixed()-1)*(24/(blocksPerHour/300))+1)**365;

        console.log("instant APR:", apr*100, "%");
        console.log("instant APY:", (apy-1)*100, "%");

        await Utils.advanceNBlock(blocksPerHour);
      }
      await vault.withdraw((new BigNumber(await vault.balanceOf(farmer1)).div(2)).toFixed(), {from: farmer1});
      farmerBalance = new BigNumber(await underlying.balanceOf(farmer1));
      console.log("Partial withdrawal:", farmerBalance.toFixed());
      await vault.withdraw(new BigNumber(await vault.balanceOf(farmer1)).toFixed(), { from: farmer1 });
      let farmerNewBalance = new BigNumber(await underlying.balanceOf(farmer1));
      Utils.assertBNGt(farmerNewBalance, farmerOldBalance);

      apr = (farmerNewBalance.toFixed()/farmerOldBalance.toFixed()-1)*(24/(blocksPerHour*hours/300))*365;
      apy = ((farmerNewBalance.toFixed()/farmerOldBalance.toFixed()-1)*(24/(blocksPerHour*hours/300))+1)**365;

      console.log("earned!");
      console.log("APR:", apr*100, "%");
      console.log("APY:", (apy-1)*100, "%");

      await strategy.withdrawAllToVault({from:governance}); // making sure can withdraw all for a next switch

    });
  });
});
