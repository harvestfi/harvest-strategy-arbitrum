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
const Strategy = artifacts.require("FluidLendStrategyMainnet_USDC");

// Developed and tested at blockNumber 443752300

// Vanilla Mocha test. Increased compatibility with tools that integrate Mocha.
describe("Mainnet Fluid Lend USDC upgrade rewards", function() {
  let accounts;

  // external contracts
  let underlying;

  // external setup
  let underlyingWhale = "0x5355A7C6E97FA179842477184D5ae1e58d712e2D";
  let fluidWhale = "0x9C89f595F5515609AD61f6FDa94beff85ae6600e";
  let usdc = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
  let weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  let fluid = "0x61E030A56D33e8260FdD81f03B162A79Fe3449Cd";
  let fluidToken;

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
    underlying = await IERC20.at("0xaf88d065e77c8cC2239327C5EDb3A432268e5831");
    console.log("Fetching Underlying at: ", underlying.address);
    fluidToken = await IERC20.at(fluid);
  }

  async function setupBalance(){
    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: underlyingWhale, value: 10e18});
    await web3.eth.sendTransaction({ from: etherGiver, to: fluidWhale, value: 10e18});

    farmerBalance = await underlying.balanceOf(underlyingWhale);
    await underlying.transfer(farmer1, farmerBalance, { from: underlyingWhale });
  }

  before(async function() {
    governance = addresses.Governance;
    accounts = await web3.eth.getAccounts();

    farmer1 = accounts[1];

    // impersonate accounts
    await impersonates([governance, underlyingWhale, addresses.ULOwner, fluidWhale]);

    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: governance, value: 10e18});
    await web3.eth.sendTransaction({ from: etherGiver, to: addresses.ULOwner, value: 10e18});

    await setupExternalContracts();
    [controller, vault, strategy] = await setupCoreProtocol({
      "existingVaultAddress": "0x58677351d11F8941c7199c49aa7379A156404972",
      "upgradeStrategy": true,
      "strategyArtifact": Strategy,
      "strategyArtifactIsUpgradable": true,
      "underlying": underlying,
      "governance": governance,
      "ULOwner": addresses.ULOwner,
      "liquidation": [
        {"uniV3": [fluid, weth]},
        {"uniV3": [fluid, weth, usdc]},
      ],
      "uniV3Fee": [
        [fluid, weth, 10000],
      ],
    });

    // whale send underlying to farmers
    await setupBalance();
  });

  describe("Happy path", function() {
    it("Farmer should earn money", async function() {
      let farmerOldBalance = new BigNumber(await underlying.balanceOf(farmer1));
      await depositVault(farmer1, underlying, vault, farmerBalance);

      let hours = 10;
      let blocksPerHour = 2400;
      let oldSharePrice;
      let newSharePrice;

      console.log(strategy.address);

      await strategy.claim(
        "0x94312a608246Cecfce6811Db84B3Ef4B2619054E",
        "11966690528512848228",
        1,
        "0x0000000000000000000000001a996cb54bb95462040408c06122d45d6cdb6096",
        738,
        [
          "0x32f2934e7d55123a97e746e07fd400d41653e04afa8c2a29fc052606922a5f5b",
          "0xe2f57f7efceeb754d8cd8dfdec311efdaa836ea151f169453bd3924de6eb2815",
          "0x6535db64d7ca272e28047486c9a92883398545e6f4c64c6f5171a305ce544d51",
          "0x23624a71ef9cb95ccf9571ea2d1f29cfe297e3736c386217a38ad10bcac39227",
          "0xdb2bf2adaac422ba5b1e5e3a7917675a1d34981fd582e8f2662300bec771e46b",
          "0x649d7f44314bc9dfe73f75aee9ed02bdba25fff8e5f9f1518ea607e536b2ea7e",
          "0x30a4cbb69695ef9e3851d43816ef53b7bc8f1217902c1e837439e1764a3e7bfd",
          "0x7d3fa194e5b9bc45ba5af6963296a3ac15c1dd1bd66aae6588026b7db73fb613",
          "0x396dbbe5f6c78bb5667d553846e311c54c71b0357df8379827eb3401a766bb93",
          "0x47100fc26de3b9a8d90a05394cea2a7ef065b9a569778b8a199d2a8a71a1e604",
          "0xf69b8beda8cc6259972ecbc1a4d5612c5f329600a833da0a3c6963dfbd6b4f44",
          "0x339e809989ecf9885b3cee397b286219c41d3d9ccec978c8b9abbadfc414cf1f",
          "0x50a02645eca497e19ae0215e2a1b19c281bb4e5f01010eb1fddb4d85028ec942",
          "0xe7102809a396d6b7cbd028cfbd58e18aede8e820b5ac77e2552240b80479312a",
          "0x900cd40df662e8c3f5af765e68c2ddd96320719025ea141b0545fce8e31cd552"
        ],
        "0x"  
      )

      for (let i = 0; i < hours; i++) {
        console.log("loop ", i);

        await fluidToken.transfer(strategy.address, new BigNumber(10e18).toFixed(), {from: fluidWhale});

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
