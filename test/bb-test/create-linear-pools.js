// Utilities
const Utils = require("../utilities/Utils.js");
const {
  impersonates,
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
const IController = artifacts.require("IController");

const Strategy = artifacts.require("NoopStrategyMainnet_USDC");

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
  let usdcVaultAddr = "0xf08CC15597f091129228982b61928a01ca7CC939";
  let usdtVaultAddr = "0x6F4866Aebc016C12Bff810da79422e3c60e70af4";
  let usdcAddr = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
  let usdtAddr = "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9";

  let usdcPoolAddr = "0xae646817e458C0bE890b81e8d880206710E3c44e";
  let usdcPoolId = "0xae646817e458c0be890b81e8d880206710e3c44e00000000000000000000039d";
  let usdcRebalancerAddr = "0x9756549A334Bd48423457D057e8EDbFAf2104b16";
  let usdtLinearPool, usdtRebalancer

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
    usdcPool = await LinearPool.at(usdcPoolAddr);
    usdcRebalancer = await LinearPoolRebalancer.at(usdcRebalancerAddr);

    await controller.addToWhitelist(usdcRebalancerAddr, {from: governance});
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
  });

  describe("Happy path", function() {
    it("Deploy USDC Linear Pool", async function() {            
      await linearPoolFactory.create(
        "Balancer Harvest Boosted USDC",
        "bb-f-USDC",
        usdc.address,
        usdcVault.address,
        new BigNumber(1e18),
        new BigNumber(1e13),
        governance,
        69
      );
    });
    it("Deposit to USDC pool", async function () {

      console.log("INITIAL STATE");
      // deposit 10 USDC to vault
      let poolERC20 = await IERC20.at(usdcPoolAddr);
      await depositVault(farmer1, usdc, usdcVault, "1000" + "000000");
      let vaultBalance = new BigNumber(await usdcVault.balanceOf(farmer1));
      let usdcBalance = new BigNumber(await usdc.balanceOf(farmer1));
      let lpBalance = new BigNumber(await poolERC20.balanceOf(farmer1));
      console.log("Farmer fUSDC balance", vaultBalance.div(1e6).toNumber());
      console.log("Farmer usdc balance", usdcBalance.div(1e6).toNumber());
      console.log("Farmer lp balance", lpBalance.div(1e18).toNumber());

      let poolTokenInfo = await bVault.getPoolTokens(usdcPoolId);
      console.log("LP fUSDC balance", new BigNumber(poolTokenInfo.balances[1]).div(1e6).toNumber());
      console.log("LP usdc balance", new BigNumber(poolTokenInfo.balances[2]).div(1e6).toNumber());
      console.log(" ");

      await usdc.approve(bVault.address, new BigNumber(1e18), {from: farmer1})
      await bVault.swap(
        [usdcPoolId, 0, usdc.address, usdcPoolAddr, 1000000000, 0],
        [farmer1, false, farmer1, false],
        0,
        Date.now() + 900000,
        {from: farmer1}
      );
      
      console.log("AFTER DEPOSIT 1000 USDC INTO LP");
      vaultBalance = new BigNumber(await usdcVault.balanceOf(farmer1));
      usdcBalance = new BigNumber(await usdc.balanceOf(farmer1));
      lpBalance = new BigNumber(await poolERC20.balanceOf(farmer1));
      console.log("Farmer fUSDC balance", vaultBalance.div(1e6).toNumber());
      console.log("Farmer usdc balance", usdcBalance.div(1e6).toNumber());
      console.log("Farmer lp balance", lpBalance.div(1e18).toNumber());

      poolTokenInfo = await bVault.getPoolTokens(usdcPoolId);
      console.log("LP fUSDC balance", new BigNumber(poolTokenInfo.balances[1]).div(1e6).toNumber());
      console.log("LP usdc balance", new BigNumber(poolTokenInfo.balances[2]).div(1e6).toNumber());
      console.log(" ");

      await usdcRebalancer.rebalance(farmer1, {from: farmer1});

      console.log("AFTER LP REBALANCE");
      vaultBalance = new BigNumber(await usdcVault.balanceOf(farmer1));
      usdcBalance = new BigNumber(await usdc.balanceOf(farmer1));
      lpBalance = new BigNumber(await poolERC20.balanceOf(farmer1));
      console.log("Farmer fUSDC balance", vaultBalance.div(1e6).toNumber());
      console.log("Farmer usdc balance", usdcBalance.div(1e6).toNumber());
      console.log("Farmer lp balance", lpBalance.div(1e18).toNumber());

      poolTokenInfo = await bVault.getPoolTokens(usdcPoolId);
      console.log("LP fUSDC balance", new BigNumber(poolTokenInfo.balances[1]).div(1e6).toNumber());
      console.log("LP usdc balance", new BigNumber(poolTokenInfo.balances[2]).div(1e6).toNumber());
      console.log(" ");


      await usdcPool.setTargets(0, new BigNumber(1500e18), {from: governance})

      await bVault.swap(
        [usdcPoolId, 0, usdc.address, usdcPoolAddr, 1000000000, 0],
        [farmer1, false, farmer1, false],
        0,
        Date.now() + 900000,
        {from: farmer1}
      );
      
      // await usdcPool.setTargets(new BigNumber(1000e18), new BigNumber(1500e18), {from: governance})

      console.log("AFTER DEPOSIT ANOTHER 1000 USDC");
      vaultBalance = new BigNumber(await usdcVault.balanceOf(farmer1));
      usdcBalance = new BigNumber(await usdc.balanceOf(farmer1));
      lpBalance = new BigNumber(await poolERC20.balanceOf(farmer1));
      console.log("Farmer fUSDC balance", vaultBalance.div(1e6).toNumber());
      console.log("Farmer usdc balance", usdcBalance.div(1e6).toNumber());
      console.log("Farmer lp balance", lpBalance.div(1e18).toNumber());

      poolTokenInfo = await bVault.getPoolTokens(usdcPoolId);
      console.log("LP fUSDC balance", new BigNumber(poolTokenInfo.balances[1]).div(1e6).toNumber());
      console.log("LP usdc balance", new BigNumber(poolTokenInfo.balances[2]).div(1e6).toNumber());
      console.log(" ");

      await usdcRebalancer.rebalance(farmer1, {from: farmer1});

      console.log("AFTER REBALANCE WITH NEW TARGETS: [0, 1500]");
      vaultBalance = new BigNumber(await usdcVault.balanceOf(farmer1));
      usdcBalance = new BigNumber(await usdc.balanceOf(farmer1));
      lpBalance = new BigNumber(await poolERC20.balanceOf(farmer1));
      console.log("Farmer fUSDC balance", vaultBalance.div(1e6).toNumber());
      console.log("Farmer usdc balance", usdcBalance.div(1e6).toNumber());
      console.log("Farmer lp balance", lpBalance.div(1e18).toNumber());

      poolTokenInfo = await bVault.getPoolTokens(usdcPoolId);
      console.log("LP fUSDC balance", new BigNumber(poolTokenInfo.balances[1]).div(1e6).toNumber());
      console.log("LP usdc balance", new BigNumber(poolTokenInfo.balances[2]).div(1e6).toNumber());
      console.log(" ");

      await usdcPool.setTargets(new BigNumber(700e18), new BigNumber(1500e18), {from: governance});

      let vaultERC20 = await IERC20.at(usdcVaultAddr);
      await vaultERC20.approve(bVault.address, new BigNumber(1e18), {from: farmer1})
      await bVault.swap(
        [usdcPoolId, 0, usdcVault.address, usdc.address, 500000000, 0],
        [farmer1, false, farmer1, false],
        0,
        Date.now() + 900000,
        {from: farmer1}
      );

      console.log("AFTER SWAP 500 fUSDC for USDC");
      vaultBalance = new BigNumber(await usdcVault.balanceOf(farmer1));
      usdcBalance = new BigNumber(await usdc.balanceOf(farmer1));
      lpBalance = new BigNumber(await poolERC20.balanceOf(farmer1));
      console.log("Farmer fUSDC balance", vaultBalance.div(1e6).toNumber());
      console.log("Farmer usdc balance", usdcBalance.div(1e6).toNumber());
      console.log("Farmer lp balance", lpBalance.div(1e18).toNumber());

      poolTokenInfo = await bVault.getPoolTokens(usdcPoolId);
      console.log("LP fUSDC balance", new BigNumber(poolTokenInfo.balances[1]).div(1e6).toNumber());
      console.log("LP usdc balance", new BigNumber(poolTokenInfo.balances[2]).div(1e6).toNumber());
      console.log(" ");

      await usdcRebalancer.rebalance(farmer1, {from: farmer1});

      console.log("AFTER REBALANCE WITH NEW TARGETS: [700, 1500]");
      vaultBalance = new BigNumber(await usdcVault.balanceOf(farmer1));
      usdcBalance = new BigNumber(await usdc.balanceOf(farmer1));
      lpBalance = new BigNumber(await poolERC20.balanceOf(farmer1));
      console.log("Farmer fUSDC balance", vaultBalance.div(1e6).toNumber());
      console.log("Farmer usdc balance", usdcBalance.div(1e6).toNumber());
      console.log("Farmer lp balance", lpBalance.div(1e18).toNumber());

      poolTokenInfo = await bVault.getPoolTokens(usdcPoolId);
      console.log("LP fUSDC balance", new BigNumber(poolTokenInfo.balances[1]).div(1e6).toNumber());
      console.log("LP usdc balance", new BigNumber(poolTokenInfo.balances[2]).div(1e6).toNumber());
      console.log(" ");

    });
  });
});
