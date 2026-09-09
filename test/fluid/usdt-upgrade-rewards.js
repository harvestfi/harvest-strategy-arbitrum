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
const Strategy = artifacts.require("FluidLendStrategyMainnet_USDT");

// Developed and tested at blockNumber 443752300

// Vanilla Mocha test. Increased compatibility with tools that integrate Mocha.
describe("Mainnet Fluid Lend USDT upgrade rewards", function() {
  let accounts;

  // external contracts
  let underlying;

  // external setup
  let underlyingWhale = "0x2C45F224b2208D454f95c84ae62022Af4336C2C8";
  let fluidWhale = "0x9C89f595F5515609AD61f6FDa94beff85ae6600e";
  let usdt = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9";
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
    underlying = await IERC20.at("0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9");
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
      "existingVaultAddress": "0x5189dcB7CDAB823915865817778032d2a6fC8108",
      "upgradeStrategy": true,
      "strategyArtifact": Strategy,
      "strategyArtifactIsUpgradable": true,
      "underlying": underlying,
      "governance": governance,
      "ULOwner": addresses.ULOwner,
      "liquidation": [
        {"uniV3": [fluid, weth]},
        {"uniV3": [fluid, weth, usdt]},
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
        "35254732457439843132",
        1,
        "0x0000000000000000000000004a03f37e7d3fc243e3f99341d36f4b829bee5e03",
        738,
        [
          "0x850ea8f27c42fe096acfbd0d858d658026630529784016b93cfa54db5ffe6a83",
          "0xcf1af6d9e1e5bd372589256757939d9fac44901dd13883322923b87b86463fc6",
          "0x80a383c526d25d2b8d3e18d267f090fafff861fe87db9ee4afbd1c74bf08d93d",
          "0x7e527fcf849756980945c49d719c89e0222f5d49bcd106626e5c519033083f04",
          "0xdc77ee4b95ee552e9bc34e23e6e85fdf76d3a84eef4febb7f1ded443d6492d50",
          "0x2627e9a1c1e6edfb047d9dc90db356cac0891874a256e67bb2394564f5d92711",
          "0x434d2ffeaff22265f71c78f088513e8ed9d55c8f88fbb6af4d42056bdd5803fd",
          "0x10fa32bd598450c8a41b4f6726c012fe4a2036e253b18f294d82d6a2fc3e1f0b",
          "0xeb7b95e962a863e825bb16c310804cc4ed3a971c2de41cd2d6e6e9c3b8d7f02b",
          "0x125faf445554ae9d48b9b4b9e02ec6361707347b02d2729b42cd0879d322605c",
          "0x28615e310dcd09e7ccf019396a78da5d9e22247a97a5fee705908b6848d642a8",
          "0x9e295f959246db64b12251c706a8669779945466d9ab5566baf842766c15162f",
          "0x9f8936fdfb3a156b502b37c267c765bce22fc8f2f4ebdd899068d90b310e4237",
          "0x1ef7f5e4626a051c554065a805f80841a468878e9476b432c6e55b8b25089968"
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
