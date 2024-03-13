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
const IVault = artifacts.require("IVault");

//const Strategy = artifacts.require("");
const Strategy = artifacts.require("LodestarFoldStrategyV2HODLMainnet_MAGIC");

const D18 = new BigNumber(Math.pow(10, 18));

// Developed and tested at blockNumber 188352500

// Vanilla Mocha test. Increased compatibility with tools that integrate Mocha.
describe("Arbitrum Mainnet Lodestar HODL Fold MAGIC", function() {
  let accounts;

  // external contracts
  let underlying;

  // external setup
  let underlyingWhale = "0x4fcE03fBb842D615BF2F863B00178A164CfBFd5c";
  let hodlVaultAddr = "0x710A1AB6Cb8412DE9613ad6c7195453Ce8b5ca71";
  let arbAddr = "0x912CE59144191C1204E64559FE8253a0e49E6548";
  let arbWhale = "0xE1f30C44Bd1c8d537BaCb5CE34740578158b006f";
  let arb;

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
    underlying = await IERC20.at("0x539bdE0d7Dbd336b79148AA742883198BBF60342");
    console.log("Fetching Underlying at: ", underlying.address);
    arb = await IERC20.at(arbAddr);
  }

  async function setupBalance(){
    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: underlyingWhale, value: 10e18});
    await web3.eth.sendTransaction({ from: etherGiver, to: arbWhale, value: 10e18});

    farmerBalance = new BigNumber(await underlying.balanceOf(underlyingWhale)).div(2);
    await underlying.transfer(farmer1, farmerBalance, { from: underlyingWhale });
  }

  before(async function() {
    governance = addresses.Governance;
    accounts = await web3.eth.getAccounts();

    farmer1 = accounts[1];

    // impersonate accounts
    await impersonates([governance, underlyingWhale, arbWhale]);

    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: governance, value: 10e18});

    await setupExternalContracts();
    hodlVault = await IVault.at(hodlVaultAddr);
    [controller, vault, strategy, potPool] = await setupCoreProtocol({
      "existingVaultAddress": "0x29C53Aeb23F5927ae97d85389Fee9628CfF29eea",
      "strategyArtifact": Strategy,
      "strategyArtifactIsUpgradable": true,
      "upgradeStrategy": true,
      "underlying": underlying,
      "governance": governance,
      "existingRewardPoolAddress" : "0x97bfE23CAD9bdf55D7Cb9635d706582c0aD12146",
    });

    // whale send underlying to farmers
    await setupBalance();
  });

  describe("Happy path", function() {
    it("Farmer should earn money", async function() {
      await underlying.transfer(strategy.address, new BigNumber(8e19), {from:farmer1});
      let farmerOldBalance = new BigNumber(await underlying.balanceOf(farmer1));
      await depositVault(farmer1, underlying, vault, farmerOldBalance);
      let farmerOldHodlBalance = new BigNumber(await hodlVault.balanceOf(farmer1));
      let fTokenBalance = new BigNumber(await vault.balanceOf(farmer1));

      let erc20Vault = await IERC20.at(vault.address);
      await erc20Vault.approve(potPool.address, fTokenBalance, {from: farmer1});
      await potPool.stake(fTokenBalance, {from: farmer1});

      let hours = 20;
      let blocksPerHour = 3600*2.2;
      let oldSharePrice;
      let newSharePrice;
      let oldHodlSharePrice;
      let newHodlSharePrice;
      let oldPotPoolBalance;
      let newPotPoolBalance;
      let hodlPrice;
      let underlyingPrice;
      let oldValue;
      let newValue;

      for (let i = 0; i < hours; i++) {
        console.log("loop ", i);

        if (i % 7 == 0) {
          await arb.transfer(strategy.address, new BigNumber(100e18), { from: arbWhale });
        }

        oldSharePrice = new BigNumber(await vault.getPricePerFullShare());
        oldHodlSharePrice = new BigNumber(await hodlVault.getPricePerFullShare());
        oldPotPoolBalance = new BigNumber(await hodlVault.balanceOf(potPool.address));
        await controller.doHardWork(vault.address, {from: governance});
        await controller.doHardWork(hodlVault.address, {from: governance});
        newSharePrice = new BigNumber(await vault.getPricePerFullShare());
        newHodlSharePrice = new BigNumber(await hodlVault.getPricePerFullShare());
        newPotPoolBalance = new BigNumber(await hodlVault.balanceOf(potPool.address));

        hodlPrice = new BigNumber(0.2507).times(D18);
        underlyingPrice = new BigNumber(1.31).times(D18);
        console.log("Hodl price:", hodlPrice.toFixed()/D18.toFixed());
        console.log("Underlying price:", underlyingPrice.toFixed()/D18.toFixed());

        oldValue = (fTokenBalance.times(oldSharePrice).times(underlyingPrice)).div(1e36).plus((oldPotPoolBalance.times(oldHodlSharePrice).times(hodlPrice)).div(1e36));
        newValue = (fTokenBalance.times(newSharePrice).times(underlyingPrice)).div(1e36).plus((newPotPoolBalance.times(newHodlSharePrice).times(hodlPrice)).div(1e36));

        console.log("old value: ", oldValue.toFixed()/D18.toFixed());
        console.log("new value: ", newValue.toFixed()/D18.toFixed());
        console.log("growth: ", newValue.toFixed() / oldValue.toFixed());

        console.log("Hodl token in potpool: ", newPotPoolBalance.toFixed());

        apr = (newValue.toFixed()/oldValue.toFixed()-1)*(24/(blocksPerHour/300))*365;
        apy = ((newValue.toFixed()/oldValue.toFixed()-1)*(24/(blocksPerHour/300))+1)**365;

        console.log("instant APR:", apr*100, "%");
        console.log("instant APY:", (apy-1)*100, "%");

        await Utils.advanceNBlock(blocksPerHour);
      }
      // withdrawAll to make sure no doHardwork is called when we do withdraw later.
      await vault.withdrawAll({ from: governance });

      // wait until all reward can be claimed by the farmer
      await Utils.waitTime(86400 * 30 * 1000);
      console.log("vaultBalance: ", fTokenBalance.toFixed());
      await potPool.exit({from: farmer1});
      await vault.withdraw(fTokenBalance.toFixed(), { from: farmer1 });
      let farmerNewBalance = new BigNumber(await underlying.balanceOf(farmer1));
      let farmerNewHodlBalance = new BigNumber(await hodlVault.balanceOf(farmer1));
      Utils.assertBNGte(farmerNewBalance, farmerOldBalance);
      Utils.assertBNGt(farmerNewHodlBalance, farmerOldHodlBalance);

      oldValue = (fTokenBalance.times(1e18).times(underlyingPrice)).div(1e36);
      newValue = (fTokenBalance.times(newSharePrice).times(underlyingPrice)).div(1e36).plus((farmerNewHodlBalance.times(newHodlSharePrice).times(hodlPrice)).div(1e36));

      apr = (newValue.toFixed()/oldValue.toFixed()-1)*(24/(blocksPerHour*hours/300))*365;
      apy = ((newValue.toFixed()/oldValue.toFixed()-1)*(24/(blocksPerHour*hours/300))+1)**365;

      console.log("Overall APR:", apr*100, "%");
      console.log("Overall APY:", (apy-1)*100, "%");

      console.log("potpool totalShare: ", (new BigNumber(await potPool.totalSupply())).toFixed());
      console.log("Hodl token in potpool: ", (new BigNumber(await hodlVault.balanceOf(potPool.address))).toFixed() );
      console.log("Farmer got hodl token from potpool: ", farmerNewHodlBalance.toFixed());
      console.log("earned!");

      await strategy.withdrawAllToVault({ from: governance }); // making sure can withdraw all for a next switch
    });
  });
});
