// Utilities
const Utils = require("../utilities/Utils.js");
const {
  impersonates,
  setupCoreProtocol,
  depositVault,
} = require("../utilities/hh-utils.js");
const { send } = require("@openzeppelin/test-helpers");

const addresses = require("../test-config.js");
const BigNumber = require("bignumber.js");
const IERC20 = artifacts.require("IERC20");

const PoolFactory = artifacts.require("ILinearPoolFactory");
const LinearPool = artifacts.require("ILinearPool");
const LinearPoolRebalancer = artifacts.require("ILinearPoolRebalancer");
const BVault = artifacts.require("IBVault");

const IVault = artifacts.require("IVault");
const IController =artifacts.require("IController");

// Developed and tested at blockNumber 65837850

// Vanilla Mocha test. Increased compatibility with tools that integrate Mocha.
describe("Deploy and check Balancer Linear Pools for Harvest vaults", function() {
  let accounts;

  // external contracts
  let usdc;
  let usdt;
  let bVault;
  let linearPoolFactory;
  let linearPoolFactoryAddr = "0xa3B9515A9c557455BC53F7a535A85219b59e8B2E";
  let bVaultAddr = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
  let usdcVaultAddr = "0x2C59C8DE53534b84581741a0db68BBA9A396deb3";
  let usdtVaultAddr = "0x6F4866Aebc016C12Bff810da79422e3c60e70af4";
  let usdcAddr = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
  let usdtAddr = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9";

  let deploymentCodeA = "0x64968C819a0D7308Fc5Bf85bEb39E4474f680c50";
  let deploymentCodeB = "0x73e779B1C50A028394f0Af91cCE69B2C5c1b0645";

  let usdcLinearPool, usdtLinearPool, usdcRebalancer, usdtRebalancer

  // external setup
  let underlyingWhale = "0xf89d7b9c864f589bbF53a82105107622B35EaA40";

  // parties in the protocol
  let governance;
  let farmer1;

  // numbers used in tests
  let farmerUSDCBalance;
  let farmerUSDTBalance;

  // Core protocol contracts
  let usdcVault;
  let usdtVault;
  let controller;

  async function setupExternalContracts() {
    usdc = await IERC20.at(usdcAddr);
    usdt = await IERC20.at(usdtAddr);
    linearPoolFactory = await PoolFactory.at(linearPoolFactoryAddr);
    bVault = await BVault.at(bVaultAddr);
    usdcVault = await IVault.at(usdcVaultAddr);
    usdtVault = await IVault.at(usdtVaultAddr);
    controller = await IController.at(addresses.Controller);
  }

  async function setupBalance(){
    let etherGiver = accounts[9];
    await send.ether(etherGiver, underlyingWhale, "1" + "000000000000000000");

    farmerUSDCBalance = await usdc.balanceOf(underlyingWhale);
    await usdc.transfer(farmer1, farmerUSDCBalance, { from: underlyingWhale });
    farmerUSDTBalance = await usdt.balanceOf(underlyingWhale);
    await usdt.transfer(farmer1, farmerUSDTBalance, { from: underlyingWhale });
  }

  before(async function() {
    governance = addresses.Governance;
    accounts = await web3.eth.getAccounts();

    farmer1 = accounts[1];

    // impersonate accounts
    await impersonates([governance, underlyingWhale]);

    let etherGiver = accounts[9];
    await send.ether(etherGiver, governance, "100" + "000000000000000000");

    await setupExternalContracts();

    // whale send underlying to farmers
    await setupBalance();

    await controller.addCodeToWhitelist(deploymentCodeA);
    await controller.addCodeToWhitelist(deploymentCodeB);
  });

  describe("Happy path", function() {
    it("Setup and check USDC Linear Pool", async function() {
      // deposit 10 USDC to vault
      await depositVault(farmer1, usdc, usdcVault, "1" + "000000");
      let vaultBalance = await usdcVault.balanceOf(farmer1);
            
      let usdcPoolAddr = await linearPoolFactory.create(
        "Balancer Harvest Boosted USDC",
        "bb-f-USDC",
        usdc.address,
        usdcVault.address,
        new BigNumber(1e18),
        new BigNumber(1e16),
        governance,
        69
      );
      console.log(usdcPoolAddr)
    });
  });
});
