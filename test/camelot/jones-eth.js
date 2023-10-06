// Utilities
const Utils = require("../utilities/Utils.js");
const { impersonates, setupCoreProtocol, depositVault } = require("../utilities/hh-utils.js");

const addresses = require("../test-config.js");
const BigNumber = require("bignumber.js");
const IERC20 = artifacts.require("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20");

const Strategy = artifacts.require("CamelotNitroStrategyMainnet_JONES_ETH");
const IXGrail = artifacts.require("IXGrail")
const IVault = artifacts.require("IVault");

const D18 = new BigNumber(Math.pow(10, 18));

//This test was developed at blockNumber 126125300

// Vanilla Mocha test. Increased compatibility with tools that integrate Mocha.
describe("Mainnet Camelot JONES-ETH HODL in xGRAIL", function () {
  let accounts;

  // external contracts
  let underlying;

  // external setup
  let underlyingWhale = "0x3Ac3BF277Ec0597d81e0Bb0071355B8E31203E9c";
  let hodlVaultAddr = "0xFA10759780304c2B8d34B051C039899dFBbcad7f";
  let grail = "0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8";
  let weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  let jones = "0x10393c20975cF177a3513071bC110f7962CD67da";

  // parties in the protocol
  let governance;
  let ulowner;
  let farmer1;

  // numbers used in tests
  let farmerBalance;

  // Core protocol contracts
  let controller;
  let vault;
  let strategy;
  let hodlVault;

  async function setupExternalContracts() {
    underlying = await IERC20.at("0x460c2c075340EbC19Cf4af68E5d83C194E7D21D0");
    console.log("Fetching Underlying at: ", underlying.address);
  }

  async function setupBalance() {
    let etherGiver = accounts[9];
    // Give whale some ether to make sure the following actions are good
    await web3.eth.sendTransaction({ from: etherGiver, to: underlyingWhale, value: 10e18 });

    farmerBalance = await underlying.balanceOf(underlyingWhale);
    await underlying.transfer(farmer1, farmerBalance, { from: underlyingWhale });
  }

  before(async function () {
    governance = addresses.Governance;
    ulowner = addresses.ULOwner;
    accounts = await web3.eth.getAccounts();

    farmer1 = accounts[1];

    // impersonate accounts
    await impersonates([governance, underlyingWhale, ulowner]);
    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: governance, value: 10e18 });
    await web3.eth.sendTransaction({ from: etherGiver, to: ulowner, value: 10e18 });

    await setupExternalContracts();
    hodlVault = await IVault.at(hodlVaultAddr);
    [controller, vault, strategy, potPool] = await setupCoreProtocol({
      "existingVaultAddress": null,
      "strategyArtifact": Strategy,
      "strategyArtifactIsUpgradable": true,
      "underlying": underlying,
      "governance": governance,
      "rewardPool": true,
      "rewardPoolConfig": {
        type: 'PotPool',
        rewardTokens: [
          hodlVault.address, // fxGrail
        ]
      },
      "liquidation": [
        { "camelot": [jones, weth, grail] },
        { "camelot": [grail, weth, jones] }
      ],
      "ULOwner": addresses.ULOwner
    });

    await strategy.setPotPool(potPool.address, { from: governance });
    await potPool.setRewardDistribution([strategy.address], true, { from: governance });
    await controller.addToWhitelist(strategy.address, { from: governance });

    // whale send underlying to farmers
    await setupBalance();
  });

  describe("Happy path", function () {
    it("Farmer should earn money", async function () {
      let farmerOldBalance = new BigNumber(await underlying.balanceOf(farmer1));
      let farmerOldHodlBalance = new BigNumber(await hodlVault.balanceOf(farmer1));
      await depositVault(farmer1, underlying, vault, farmerBalance);
      let fTokenBalance = new BigNumber(await vault.balanceOf(farmer1));

      let erc20Vault = await IERC20.at(vault.address);
      await erc20Vault.approve(potPool.address, fTokenBalance, { from: farmer1 });
      await potPool.stake(fTokenBalance, { from: farmer1 });

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
      let underlyingPrice;
      let oldValue;
      let newValue;
      for (let i = 0; i < hours; i++) {
        console.log("loop ", i);

        oldSharePrice = new BigNumber(await vault.getPricePerFullShare());
        oldHodlSharePrice = new BigNumber(await hodlVault.getPricePerFullShare());
        oldPotPoolBalance = new BigNumber(await hodlVault.balanceOf(potPool.address));
        await controller.doHardWork(vault.address, { from: governance });
        await controller.doHardWork(hodlVault.address, { from: governance });
        newSharePrice = new BigNumber(await vault.getPricePerFullShare());
        newHodlSharePrice = new BigNumber(await hodlVault.getPricePerFullShare());
        newPotPoolBalance = new BigNumber(await hodlVault.balanceOf(potPool.address));

        hodlPrice = new BigNumber(769.71).times(D18);
        underlyingPrice = new BigNumber(1903205.45 / 23975.9).times(D18);
        console.log("Hodl price:", hodlPrice.toFixed() / D18.toFixed());
        console.log("Underlying price:", underlyingPrice.toFixed() / D18.toFixed());

        oldValue = (fTokenBalance.times(oldSharePrice).times(underlyingPrice)).div(1e36).plus((oldPotPoolBalance.times(oldHodlSharePrice).times(hodlPrice)).div(1e36));
        newValue = (fTokenBalance.times(newSharePrice).times(underlyingPrice)).div(1e36).plus((newPotPoolBalance.times(newHodlSharePrice).times(hodlPrice)).div(1e36));

        console.log("old value: ", oldValue.toFixed() / D18.toFixed());
        console.log("new value: ", newValue.toFixed() / D18.toFixed());
        console.log("growth: ", newValue.toFixed() / oldValue.toFixed());

        console.log("Hodl token in potpool: ", newPotPoolBalance.toFixed());

        apr = (newValue.toFixed() / oldValue.toFixed() - 1) * (24 / (blocksPerHour / 300)) * 365;
        apy = ((newValue.toFixed() / oldValue.toFixed() - 1) * (24 / (blocksPerHour / 300)) + 1) ** 365;

        console.log("instant APR:", apr * 100, "%");
        console.log("instant APY:", (apy - 1) * 100, "%");

        await Utils.advanceNBlock(blocksPerHour);
      }
      // withdrawAll to make sure no doHardwork is called when we do withdraw later.
      await vault.withdrawAll({ from: governance });

      // wait until all reward can be claimed by the farmer
      await Utils.waitTime(86400 * 30 * 1000);
      console.log("vaultBalance: ", fTokenBalance.toFixed());
      await potPool.exit({ from: farmer1 });
      await vault.withdraw(fTokenBalance.toFixed(), { from: farmer1 });
      let farmerNewBalance = new BigNumber(await underlying.balanceOf(farmer1));
      let farmerNewHodlBalance = new BigNumber(await hodlVault.balanceOf(farmer1));
      Utils.assertBNGte(farmerNewBalance, farmerOldBalance);
      Utils.assertBNGt(farmerNewHodlBalance, farmerOldHodlBalance);

      oldValue = (fTokenBalance.times(1e18).times(underlyingPrice)).div(1e36);
      newValue = (fTokenBalance.times(newSharePrice).times(underlyingPrice)).div(1e36).plus((farmerNewHodlBalance.times(newHodlSharePrice).times(hodlPrice)).div(1e36));

      apr = (newValue.toFixed() / oldValue.toFixed() - 1) * (24 / (blocksPerHour * hours / 300)) * 365;
      apy = ((newValue.toFixed() / oldValue.toFixed() - 1) * (24 / (blocksPerHour * hours / 300)) + 1) ** 365;

      console.log("Overall APR:", apr * 100, "%");
      console.log("Overall APY:", (apy - 1) * 100, "%");

      console.log("potpool totalShare: ", (new BigNumber(await potPool.totalSupply())).toFixed());
      console.log("Hodl token in potpool: ", (new BigNumber(await hodlVault.balanceOf(potPool.address))).toFixed());
      console.log("Farmer got hodl token from potpool: ", farmerNewHodlBalance.toFixed());
      console.log("earned!");

      await strategy.withdrawAllToVault({ from: governance }); // making sure can withdraw all for a next switch
    });
  });
});
