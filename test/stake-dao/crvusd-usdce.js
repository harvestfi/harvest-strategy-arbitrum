// Utilities
const Utils = require("../utilities/Utils.js");
const { impersonates, setupCoreProtocol, depositVault } = require("../utilities/hh-utils.js");
const addresses = require("../test-config.js");

const BigNumber = require("bignumber.js");
const IERC20 = artifacts.require("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20");

const Strategy = artifacts.require("StakeDaoStrategyMainnet_crvUSD_USDCe");

//This test was developed at blockNumber 447335000

// Vanilla Mocha test. Increased compatibility with tools that integrate Mocha.
describe("Arbitrum Mainnet StakeDao crvUSD-USDCe", function() {
  let accounts;

  // external contracts
  let underlying;

  // external setup
  let underlyingWhale = "0xB465a2962B7561a90dB5AF9bDf93351702a00A2c";
  let crvWhale = "0x02DD8D88754Be283970841c66592d3ae3020Fc7F";
  let crv = "0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978";
  let weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  let crvusd = "0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5";
  let crvToken;
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
    underlying = await IERC20.at("0x3aDf984c937FA6846E5a24E0A68521Bdaf767cE1");
    crvToken = await IERC20.at(crv);
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

    await web3.eth.sendTransaction({ from: accounts[8], to: governance, value: 10e18});
    await web3.eth.sendTransaction({ from: accounts[8], to: crvWhale, value: 10e18});
    await web3.eth.sendTransaction({ from: accounts[8], to: addresses.ULOwner, value: 10e18});

    farmer1 = accounts[1];

    // impersonate accounts
    await impersonates([governance, underlyingWhale, crvWhale, addresses.ULOwner]);

    await setupExternalContracts();
    [controller, vault, strategy] = await setupCoreProtocol({
      "existingVaultAddress": null,
      "strategyArtifact": Strategy,
      "strategyArtifactIsUpgradable": true,
      "underlying": underlying,
      "governance": governance,
      "liquidation": [
        {"curve": [weth, crvusd]},
      ],
      "curveSetup": [
        [weth, crvusd, "0x82670f35306253222F8a165869B28c64739ac62e", [2, 0, 1, 3, 3]],
      ],
      "ULOwner": addresses.ULOwner,
    });

    // whale send underlying to farmers
    await setupBalance();
  });

  describe("Happy path", function() {
    it("Farmer should earn money", async function() {
      let farmerOldBalance = new BigNumber(await underlying.balanceOf(farmer1));
      await depositVault(farmer1, underlying, vault, farmerOldBalance);
      let fTokenBalance = new BigNumber(await vault.balanceOf(farmer1));

      // Using half days is to simulate how we doHardwork in the real world
      let hours = 10;
      let blocksPerHour = 2400;
      let oldSharePrice;
      let newSharePrice;
      for (let i = 0; i < hours; i++) {
        console.log("loop ", i);
        await crvToken.transfer(strategy.address, new BigNumber(1e18), {from: crvWhale});

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
      fTokenBalance = new BigNumber(await vault.balanceOf(farmer1));
      await vault.withdraw(fTokenBalance, { from: farmer1 });
      let farmerNewBalance = new BigNumber(await underlying.balanceOf(farmer1));
      Utils.assertBNGt(farmerNewBalance, farmerOldBalance);

      apr = (farmerNewBalance.toFixed()/farmerOldBalance.toFixed()-1)*(24/(blocksPerHour*hours/300))*365;
      apy = ((farmerNewBalance.toFixed()/farmerOldBalance.toFixed()-1)*(24/(blocksPerHour*hours/300))+1)**365;

      console.log("earned!");
      console.log("Overall APR:", apr*100, "%");
      console.log("Overall APY:", (apy-1)*100, "%");

      await strategy.withdrawAllToVault({ from: governance }); // making sure can withdraw all for a next switch
    });
  });
});