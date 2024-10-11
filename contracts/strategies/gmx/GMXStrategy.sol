// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/gmx/IReader.sol";
import "../../base/interface/gmx/IMarket.sol";
import "../../base/interface/gmx/IExchangeRouter.sol";

contract GMXStrategy is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _EXCHANGE_ROUTER_SLOT = 0x37102ee245290fca7b7083aa93785ed04d2277eb4da3e0f305fc09592036c401;
  bytes32 internal constant _MARKET_SLOT = 0x7e894854bb2aa938fcac0eb9954ddb51bd061fc228fb4e5b8e859d96c06bfaa0;
  bytes32 internal constant _READER_SLOT = 0x18c62578c303d051e8cff10c8b4af39508d0ad6a2f398ce12331fd64368e8100;
  bytes32 internal constant _DEPOSIT_VAULT_SLOT = 0xb0598bc38333ab6eeb7272aded2335ca73c3fd494cec5ce1f0849cce000c3925;
  bytes32 internal constant _WITHDRAW_VAULT_SLOT = 0x65c967117bb0f9ef871538fd2bba12ca5f9d9ffa82f6b0f94c7f86b0c1575d56;

  // this would be reset on each upgrade
  address[] public rewardTokens;

  constructor() BaseUpgradeableStrategy() {
    assert(_EXCHANGE_ROUTER_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.exchangeRouter")) - 1));
    assert(_MARKET_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.market")) - 1));
    assert(_READER_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.reader")) - 1));
    assert(_DEPOSIT_VAULT_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.depositVault")) - 1));
    assert(_WITHDRAW_VAULT_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.withdrawVault")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _exchangeRouter,
    address _market,
    address _reader,
    address _depositVault,
    address _withdrawVault,
    address _rewardToken
  )
  public initializer {
    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _market,
      _rewardToken,
      harvestMSIG
    );

    address dataStore = IMarket(_market).dataStore();
    IMarket.Props memory marketData = IReader(_reader).getMarket(dataStore, _market);

    require(marketData.longToken == _underlying && marketData.shortToken == _underlying, "Underlying mismatch");

    _setMarket(_market);
    _setExchangeRouter(_exchangeRouter);
    _setReader(_reader);
    _setDepositVault(_depositVault);
    _setWithdrawVault(_withdrawVault);
  }

  function depositArbCheck() public pure returns (bool) {
    // there's no arb here.
    return true;
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying());
  }

  /**
  * The strategy invests by supplying the underlying as a collateral.
  */
  function _investAllUnderlying() internal onlyNotPausedInvesting {
    address _underlying = underlying();
    uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
    if (underlyingBalance > 0) {
      _deposit(underlyingBalance);
    }
  }

  function withdrawAllToVault() public restricted {
    _liquidateRewards();
    address _underlying = underlying();
    _withdrawAll();
    if (IERC20(_underlying).balanceOf(address(this)) > 0) {
      IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
    }
  }

  function emergencyExit() external onlyGovernance {
    _withdrawAll();
    _setPausedInvesting(true);
  }

  function continueInvesting() public onlyGovernance {
    _setPausedInvesting(false);
  }

  function withdrawToVault(uint256 amountUnderlying) public restricted {
    address _underlying = underlying();
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    if (amountUnderlying <= balance) {
      IERC20(_underlying).safeTransfer(vault(), amountUnderlying);
      return;
    }
    uint256 toWithdraw = amountUnderlying.sub(balance);
    // get some of the underlying
    _withdraw(toWithdraw);
    balance = IERC20(_underlying).balanceOf(address(this));
    // transfer the amount requested (or the amount we have) back to vault()
    IERC20(_underlying).safeTransfer(vault(), Math.min(amountUnderlying, balance));
    balance = IERC20(_underlying).balanceOf(address(this));
    if (balance > 0) {
      _investAllUnderlying();
    }
  }

  /**
  * Withdraws all assets, liquidates XVS, and invests again in the required ratio.
  */
  function doHardWork() public restricted {
    _liquidateRewards();
    _investAllUnderlying();
  }

  /**
  * Salvages a token.
  */
  function salvage(address recipient, address token, uint256 amount) public onlyGovernance {
    // To make sure that governance cannot come in and take away the coins
    require(!unsalvagableTokens(token), "token is defined as not salvagable");
    IERC20(token).safeTransfer(recipient, amount);
  }

  function addRewardToken(address _token) public onlyGovernance {
    rewardTokens.push(_token);
  }

  function _liquidateRewards() internal {
    if (!sell()) {
      // Profits can be disabled for possible simplified and rapid exit
      emit ProfitsNotCollected(sell(), false);
      return;
    }
  }

  /**
  * Returns the current balance.
  */
  function investedUnderlyingBalance() public view returns (uint256) {
    return IERC20(market()).balanceOf(address(this));
  }

  function _deposit(uint256 amount) internal {
    address _market = market();
    address _underlying = underlying();
    address _depositVault = depositVault();
    address _exchangeRouter = exchangeRouter();
    bytes[] memory data = new bytes[](3);
    data[0] = abi.encodeWithSelector(
      IExchangeRouter.sendWnt.selector,
      _depositVault,
      1e16
    );
    data[1] = abi.encodeWithSelector(
      IExchangeRouter.sendTokens.selector,
      _underlying,
      _depositVault,
      amount
    );
    data[2] = abi.encodeWithSelector(
      IExchangeRouter.createDeposit.selector,
      IExchangeRouter.CreateDepositParams({
        receiver: address(this), //receiver
        callbackContract: address(0), //callbackContract
        uiFeeReceiver: address(0), //uiFeeReceiver
        market: _market, //market
        initialLongToken: _underlying, //initialLongToken
        initialShortToken: _underlying, //initialShortToken
        longTokenSwapPath: new address[](0), //longTokenSwapPath
        shortTokenSwapPath: new address[](0), //shortTokenSwapPath
        minMarketTokens: 1, //minMarketTokens
        shouldUnwrapNativeToken: false, //shouldUnwrapNativeToken
        executionFee: 1e16, //executionFee
        callbackGasLimit: 0 //callbackGasLimit
      })
    );
    IERC20(_underlying).safeApprove(address(0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6), 0);
    IERC20(_underlying).safeApprove(address(0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6), amount);
    IExchangeRouter(_exchangeRouter).multicall{value: 1e16}(data);
  }

  function _withdraw(uint256 amount) internal {
  }

  function _withdrawAll() internal {
  }

  function _setMarket (address _target) internal {
    setAddress(_MARKET_SLOT, _target);
  }

  function market() public view returns (address) {
    return getAddress(_MARKET_SLOT);
  }

  function _setExchangeRouter (address _target) internal {
    setAddress(_EXCHANGE_ROUTER_SLOT, _target);
  }

  function exchangeRouter() public view returns (address) {
    return getAddress(_EXCHANGE_ROUTER_SLOT);
  }

  function _setReader (address _target) internal {
    setAddress(_READER_SLOT, _target);
  }

  function reader() public view returns (address) {
    return getAddress(_READER_SLOT);
  }

  function _setDepositVault (address _target) internal {
    setAddress(_DEPOSIT_VAULT_SLOT, _target);
  }

  function depositVault() public view returns (address) {
    return getAddress(_DEPOSIT_VAULT_SLOT);
  }

  function _setWithdrawVault (address _target) internal {
    setAddress(_WITHDRAW_VAULT_SLOT, _target);
  }

  function withdrawVault() public view returns (address) {
    return getAddress(_WITHDRAW_VAULT_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }

  receive() external payable {}
}