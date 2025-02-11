// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../base/interface/gmx/IReader.sol";
import "../../base/interface/gmx/IDataStore.sol";
import "../../base/interface/gmx/IOracle.sol";
import "../../base/interface/gmx/IPriceFeed.sol";

contract GMXViewer is Ownable {

  using SafeMath for uint256;

  uint256 public constant FLOAT_PRECISION = 10 ** 30;
  bytes32 public constant PRICE_FEED = keccak256(abi.encode("PRICE_FEED"));
  bytes32 public constant PRICE_FEED_HEARTBEAT_DURATION = keccak256(abi.encode("PRICE_FEED_HEARTBEAT_DURATION"));

  address public dataStore;
  address public oracle;
  address public reader;

  constructor (
    address _dataStore,
    address _oracle,
    address _reader
  ) {
    dataStore = _dataStore;
    oracle = _oracle;
    reader = _reader;
  }

  function setDataStore(address value) external onlyOwner {
    dataStore = value;
  }

  function setOracle(address value) external onlyOwner {
    oracle = value;
  }

  function setReader(address value) external onlyOwner {
    reader = value;
  }

  function _priceFeedKey(address token) internal pure returns (bytes32) {
    return keccak256(abi.encode(PRICE_FEED, token));
  }

  function _priceFeedHeartbeatDurationKey(address token) internal pure returns (bytes32) {
    return keccak256(abi.encode(PRICE_FEED_HEARTBEAT_DURATION, token));
  }

  function _getMarketPrices(IReader.MarketProps memory marketProps, bool stalenessCheck)
    internal view returns (IReader.MarketPrices memory marketPrices) {
    marketPrices.indexTokenPrice = _getPriceFeedPrice(marketProps.indexToken, stalenessCheck);
    marketPrices.longTokenPrice = _getPriceFeedPrice(marketProps.longToken, stalenessCheck);
    marketPrices.shortTokenPrice = _getPriceFeedPrice(marketProps.shortToken, stalenessCheck);
  }

  function _getPriceFeedPrice(address token, bool stalenessCheck)
    internal view returns (IReader.PriceProps memory price) {
    (, int256 latestAnswer, , uint256 updatedAt, ) = IPriceFeed(
      IDataStore(dataStore).getAddress(_priceFeedKey(token))
    ).latestRoundData();

    if (stalenessCheck) {
      uint256 heartbeatDuration = IDataStore(dataStore).getUint(
        _priceFeedHeartbeatDurationKey(token)
      );
      if (block.timestamp > updatedAt && block.timestamp - updatedAt > heartbeatDuration) {
        revert("Stale PriceFeed");
      }
    }

    uint256 multipler = IOracle(oracle).getPriceFeedMultiplier(dataStore, token);
    uint256 adjustedPrice = uint256(latestAnswer).mul(multipler).div(FLOAT_PRECISION);
    return IReader.PriceProps({min: adjustedPrice, max: adjustedPrice});
  }

  function getWithdrawalAmountOut(address market, uint256 amount, bool stalenessCheck) external view returns (uint256) {
    IReader.MarketProps memory marketData = IReader(reader).getMarket(dataStore, market);
    IReader.MarketPrices memory marketPrices = _getMarketPrices(marketData, stalenessCheck);

    (uint256 longAmount, uint256 shortAmount) = IReader(reader).getWithdrawalAmountOut(
      dataStore,
      marketData,
      marketPrices,
      amount,
      address(0),
      IReader.SwapPricingType.TwoStep
    );
    return longAmount + shortAmount;
  }

  function getDepositAmountOut(address market, uint256 amount, bool stalenessCheck) external view returns (uint256) {
    IReader.MarketProps memory marketData = IReader(reader).getMarket(dataStore, market);
    IReader.MarketPrices memory marketPrices = _getMarketPrices(marketData, stalenessCheck);

    return IReader(reader).getDepositAmountOut(
      dataStore,
      marketData,
      marketPrices,
      amount,
      0,
      address(0),
      IReader.SwapPricingType.TwoStep,
      false
    );
  }
}