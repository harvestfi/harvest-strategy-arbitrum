// Utilities
const Utils = require("../../utilities/Utils.js");
const {
  impersonates,
  setupCoreProtocol,
  depositVault,
} = require("../../utilities/hh-utils.js");

const addresses = require("../../test-config.js");
const BigNumber = require("bignumber.js");
const IERC20 = artifacts.require("IERC20");
const IMorphoVaultV2 = artifacts.require("IMorphoVaultV2");

const Strategy = artifacts.require("MorphoVaultStrategyMainnet_KPKY_EURe_V2");

// Developed and tested at blockNumber 521420000

// Exit paths on an 18 decimal underlying. The RewardForwarder on Arbitrum swaps the fee as
// it receives it, and a fee of a few thousand wei of EURe comes out of that swap as nothing,
// which reverts it. That is why this strategy raises `feeFloor()` to 1e15: the deposit here
// is small and the wait short, so the fee accrued is far below that and has to stay pending
// instead of being sent off to a swap it cannot survive.
describe("Arbitrum Mainnet Morpho Vault V2 KPK EURe Yield exit paths", function() {
  let accounts;

  // external contracts
  let underlying;

  // external setup
  let underlyingWhale = "0x476756C3d75A05757E3e8abaD6736EA6AB14675f";
  let eure = "0x0c06cCF38114ddfc35e07427B9424adcca9F44F8";
  let usdc = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
  let weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  // the Morpho vault's only adapter, and two of the markets behind it
  let adapter = "0x3360b4F6B753dafE68F2EaFC96A854C0B48B8Ff7";
  let irm = "0x66F30587FB8D4206918deb78ecA7d5eBbafD06DA";
  let wbtcMarket = web3.eth.abi.encodeParameters(
    ["address", "address", "address", "address", "uint256"],
    [eure, "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f", "0x979353e39dfD189b49aaDaFD01F1944C07Bb386B", irm, "860000000000000000"]
  );
  let wstethMarket = web3.eth.abi.encodeParameters(
    ["address", "address", "address", "address", "uint256"],
    [eure, "0x5979D7b546E38E414F7E9822514be443A4800529", "0xFE4D474E84869FC77AE608A7b7c413476ce5ACc9", irm, "860000000000000000"]
  );

  // parties in the protocol
  let governance;
  let farmer1;

  // numbers used in tests - small on purpose, see the note above
  let farmerBalance = new BigNumber(200e18).toFixed();

  // Core protocol contracts
  let controller;
  let vault;
  let strategy;

  async function setupExternalContracts() {
    underlying = await IERC20.at(eure);
    console.log("Fetching Underlying at: ", underlying.address);
  }

  async function setupBalance(){
    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: underlyingWhale, value: 10e18});
    await underlying.transfer(farmer1, farmerBalance, { from: underlyingWhale });
  }

  before(async function() {
    governance = addresses.Governance;
    accounts = await web3.eth.getAccounts();

    farmer1 = accounts[1];

    await impersonates([governance, underlyingWhale, addresses.ULOwner]);

    let etherGiver = accounts[9];
    await web3.eth.sendTransaction({ from: etherGiver, to: governance, value: 10e18});
    await web3.eth.sendTransaction({ from: etherGiver, to: addresses.ULOwner, value: 10e18});

    await setupExternalContracts();
    [controller, vault, strategy] = await setupCoreProtocol({
      "existingVaultAddress": null,
      "strategyArtifact": Strategy,
      "strategyArtifactIsUpgradable": true,
      "underlying": underlying,
      "governance": governance,
      "liquidation": [
        {"uniV3": [eure, usdc, weth]},
        {"uniV3": [weth, usdc, eure]},
      ],
      "uniV3Fee": [
        [eure, usdc, 500],
        [usdc, weth, 500],
      ],
      "ULOwner": addresses.ULOwner,
    });

    await setupBalance();

    await depositVault(farmer1, underlying, vault, farmerBalance);
    await controller.doHardWork(vault.address, { from: governance });
  });

  describe("Exit paths", function() {
    it("Keeps a fee under the floor behind instead of swapping dust", async function() {
      await Utils.waitHours(1);

      await strategy.withdrawAllToVault({ from: governance });

      const pendingFee = new BigNumber(await strategy.pendingFee());
      const idle = new BigNumber(await underlying.balanceOf(strategy.address));
      const invested = new BigNumber(await strategy.investedUnderlyingBalance());
      console.log("pending fee kept in the strategy: ", pendingFee.toFixed());
      console.log("idle underlying in the strategy:  ", idle.toFixed());
      console.log("investedUnderlyingBalance:        ", invested.toFixed());

      // far more than the 1e3 the other strategies use, and still not worth a swap
      Utils.assertBNGt(pendingFee, 1e3);
      Utils.assertBNGte(new BigNumber(await strategy.feeFloor()), pendingFee);
      // and it is still backed by underlying the strategy actually holds
      Utils.assertBNGte(idle, pendingFee);

      const sharePrice = new BigNumber(await vault.getPricePerFullShare());
      console.log("share price after the exit: ", sharePrice.toFixed());
      Utils.assertBNGt(sharePrice, 0);

      const farmerBefore = new BigNumber(await underlying.balanceOf(farmer1));
      await vault.withdraw(new BigNumber(await vault.balanceOf(farmer1)).toFixed(), { from: farmer1 });
      const farmerAfter = new BigNumber(await underlying.balanceOf(farmer1));
      const withdrawn = farmerAfter.minus(farmerBefore);
      console.log("farmer withdrew: ", withdrawn.toFixed(), " deposited: ", farmerBalance);
      Utils.assertBNGte(withdrawn, new BigNumber(farmerBalance));
      assert.equal(
        withdrawn.minus(farmerBalance).lte(1e16),
        true,
        "farmer should not withdraw more than the deposit plus the hour's yield"
      );
    });

    it("Governance can deallocate from several markets and withdraw", async function() {
      const deposit = new BigNumber(10000e18).toFixed();
      await underlying.transfer(farmer1, deposit, { from: underlyingWhale });
      await depositVault(farmer1, underlying, vault, deposit);
      await controller.doHardWork(vault.address, { from: governance });

      const fromWbtc = new BigNumber(3000e18);
      const fromWsteth = new BigNumber(2000e18);
      const amount = fromWbtc.plus(fromWsteth);
      // the Morpho vault charges this share of what is deallocated, rounded up
      const penaltyRate = new BigNumber(await (await IMorphoVaultV2.at(await strategy.morphoVault())).forceDeallocatePenalty(adapter));
      const expectedPenalty = amount.times(penaltyRate).div(1e18).integerValue(BigNumber.ROUND_CEIL);
      console.log("penalty rate: ", penaltyRate.toFixed(), " expected penalty: ", expectedPenalty.toFixed());
      Utils.assertBNGt(expectedPenalty, 0);

      const vaultBefore = new BigNumber(await underlying.balanceOf(vault.address));
      const totalBefore = new BigNumber(await vault.underlyingBalanceWithInvestment());

      const tx = await strategy.forceWithdrawToVault(
        [adapter, adapter],
        [wbtcMarket, wstethMarket],
        [fromWbtc.toFixed(), fromWsteth.toFixed()],
        amount.toFixed(),
        expectedPenalty.plus(10).toFixed(),
        { from: governance }
      );
      const forced = tx.logs.find(log => log.event === "ForcedWithdrawal");
      const paid = new BigNumber(forced.args.penalty);

      const vaultAfter = new BigNumber(await underlying.balanceOf(vault.address));
      const totalAfter = new BigNumber(await vault.underlyingBalanceWithInvestment());
      console.log("vault received: ", vaultAfter.minus(vaultBefore).toFixed());
      console.log("penalty paid:   ", paid.toFixed());

      Utils.assertBNEq(vaultAfter.minus(vaultBefore), amount);
      Utils.assertBNGte(paid, expectedPenalty.minus(10));
      Utils.assertBNGte(expectedPenalty.plus(10), paid);
      Utils.assertBNEq(await strategy.storedSupplied(), await strategy.currentSupplied());
      // all the vault as a whole lost is the penalty
      Utils.assertBNGte(totalAfter.plus(expectedPenalty).plus(10), totalBefore);
    });
  });
});
