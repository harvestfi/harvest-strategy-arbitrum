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

//const Strategy = artifacts.require("");
const Strategy = artifacts.require("XGrailStrategyV3Mainnet_XGrail");
const IXGrail = artifacts.require("IXGrail")

// Developed and tested at blockNumber 219069100

// Vanilla Mocha test. Increased compatibility with tools that integrate Mocha.
describe("Arbitrum Mainnet Camelot xGRAIL V3 Upgrade", function() {
  let accounts;

  // external contracts
  let underlying;

  // external setup
  let underlyingWhale = "0x655ECbed357138FeCB5Ee2126ea7B77439638AA5";
  let camelotGovernance = "0x460d0F7B75412592D14440857f715ec28861c2D7";
  let dmt = "0x8B0E6f19Ee57089F7649A455D89D7bC6314D04e8";
  let usdce = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
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
      "existingVaultAddress": "0xFA10759780304c2B8d34B051C039899dFBbcad7f",
      "strategyArtifact": Strategy,
      "strategyArtifactIsUpgradable": true,
      "upgradeStrategy": true,
      "underlying": underlying,
      "governance": governance,
      "liquidation": [
        {"camelotV3": [dmt, usdce, grail]},
      ]
    });

    let xGrail = await IXGrail.at("0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b");
    await xGrail.updateTransferWhitelist(underlyingWhale, true, {from: camelotGovernance});

    // whale send underlying to farmers
    await setupBalance();

    await strategy.addRewardToken(dmt, false, false, {from: governance});
  });

  describe("Happy path", function() {
    it("Farmer should earn money", async function() {
      let farmerOldBalance = new BigNumber(await underlying.balanceOf(farmer1));
      console.log(farmerOldBalance.toFixed())
      await depositVault(farmer1, underlying, vault, farmerBalance);

      let hours = 10;
      let blocksPerHour = 3600;
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
