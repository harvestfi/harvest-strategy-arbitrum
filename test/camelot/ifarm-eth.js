// Utilities
const Utils = require("../utilities/Utils.js");
const { impersonates, setupCoreProtocol, depositVault } = require("../utilities/hh-utils.js");

const addresses = require("../test-config.js");
const { send } = require("@openzeppelin/test-helpers");
const BigNumber = require("bignumber.js");
const IERC20 = artifacts.require("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20");

const HodlStrategy = artifacts.require("XGrailStrategyMainnet_XGrail");
const Strategy = artifacts.require("CamelotNitroIFarmStrategyMainnet_iFARM_ETH");
const IXGrail = artifacts.require("IXGrail")

const D18 = new BigNumber(Math.pow(10, 18));

//This test was developed at blockNumber 93361850

// Vanilla Mocha test. Increased compatibility with tools that integrate Mocha.
describe("Mainnet Camelot iFARM-ETH HODL in xGRAIL", function() {
  let accounts;

  // external contracts
  let underlying;

  // external setup
  let underlyingWhale = "0x6a74649aCFD7822ae8Fb78463a9f2192752E5Aa2";
  let hodlUnderlying = "0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b";
  let iFarmAddr = "0x9dCA587dc65AC0a043828B0acd946d71eb8D46c1";
  let iFarm;
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
    underlying = await IERC20.at("0xD2A7084369cC93672b2CA868757a9f327e3677a4");
    iFarm = await IERC20.at(iFarmAddr);
    console.log("Fetching Underlying at: ", underlying.address);
  }

  async function setupBalance(){
    let etherGiver = accounts[9];
    // Give whale some ether to make sure the following actions are good
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
    [controller, hodlVault, hodlStrategy] = await setupCoreProtocol({
      "existingVaultAddress": null,
      "strategyArtifact": HodlStrategy,
      "strategyArtifactIsUpgradable": true,
      "underlying": await IERC20.at(hodlUnderlying),
      "governance": governance,
    });
    [controller, vault, strategy, potPool] = await setupCoreProtocol({
      "existingVaultAddress": null,
      "strategyArtifact": Strategy,
      "strategyArtifactIsUpgradable": true,
      "underlying": underlying,
      "governance": governance,
      "rewardPool" : true,
      "rewardPoolConfig": {
        type: 'PotPool',
        rewardTokens: [
          hodlVault.address, // fxGrail
          iFarmAddr
        ]
      },
      "liquidation": [{"camelot": [usdc, grail]}, {"camelot": [grail, usdc]}, {"camelot": [weth, usdc, grail]}, {"camelot": [grail, usdc, weth]}]
    });

    await strategy.setXGrailVault(hodlVault.address, {from: governance});
    await strategy.setPotPool(potPool.address, {from: governance});
    await potPool.setRewardDistribution([strategy.address], true, {from: governance});
    await controller.addToWhitelist(strategy.address, {from: governance});

    xGrail = await IXGrail.at("0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b");
    await xGrail.updateTransferWhitelist(hodlVault.address, true, {from: camelotGovernance});

    await controller.setUniversalLiquidator(addresses.UniversalLiquidator, {from: governance});
    await controller.setRewardForwarder(addresses.RewardForwarder, {from: governance});

    // whale send underlying to farmers
    await setupBalance();
  });

  describe("Happy path", function() {
    it("Farmer should earn money", async function() {
      let farmerOldBalance = new BigNumber(await underlying.balanceOf(farmer1));
      let farmerOldHodlBalance = new BigNumber(await hodlVault.balanceOf(farmer1));
      await depositVault(farmer1, underlying, vault, farmerBalance);
      let fTokenBalance = new BigNumber(await vault.balanceOf(farmer1));

      let erc20Vault = await IERC20.at(vault.address);
      await erc20Vault.approve(potPool.address, fTokenBalance, {from: farmer1});
      await potPool.stake(fTokenBalance, {from: farmer1});

      // Using half days is to simulate how we doHardwork in the real world
      let hours = 10;
      let blocksPerHour = 3600;
      let oldSharePrice;
      let newSharePrice;
      let oldHodlSharePrice;
      let newHodlSharePrice;
      let oldPotPoolBalance;
      let newPotPoolBalance;
      let hodlPrice;
      let iFarmPrice;
      let underlyingPrice;
      let oldValue;
      let newValue;
      for (let i = 0; i < hours; i++) {
        console.log("loop ", i);

        oldSharePrice = new BigNumber(await vault.getPricePerFullShare());
        oldHodlSharePrice = new BigNumber(await hodlVault.getPricePerFullShare());
        oldPotPoolBalance = new BigNumber(await hodlVault.balanceOf(potPool.address));
        oldIFarmBalance = new BigNumber(await iFarm.balanceOf(potPool.address));
        await controller.doHardWork(vault.address, {from: governance});
        await controller.doHardWork(hodlVault.address, {from: governance});
        newSharePrice = new BigNumber(await vault.getPricePerFullShare());
        newHodlSharePrice = new BigNumber(await hodlVault.getPricePerFullShare());
        newPotPoolBalance = new BigNumber(await hodlVault.balanceOf(potPool.address));
        newIFarmBalance = new BigNumber(await iFarm.balanceOf(potPool.address));

        hodlPrice = new BigNumber(1454.87).times(D18);
        underlyingPrice = new BigNumber(100000/187.4).times(D18);
        iFarmPrice = new BigNumber(50000/1308.2).times(D18);
        console.log("Hodl price:", hodlPrice.toFixed()/D18.toFixed());
        console.log("Underlying price:", underlyingPrice.toFixed()/D18.toFixed());
        console.log("iFARM price:", iFarmPrice.toFixed()/D18.toFixed());

        oldValue = (fTokenBalance.times(oldSharePrice).times(underlyingPrice)).div(1e36).plus((oldPotPoolBalance.times(oldHodlSharePrice).times(hodlPrice)).div(1e36)).plus(oldIFarmBalance.times(iFarmPrice).div(1e18));
        newValue = (fTokenBalance.times(newSharePrice).times(underlyingPrice)).div(1e36).plus((newPotPoolBalance.times(newHodlSharePrice).times(hodlPrice)).div(1e36)).plus(newIFarmBalance.times(iFarmPrice).div(1e18));

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
