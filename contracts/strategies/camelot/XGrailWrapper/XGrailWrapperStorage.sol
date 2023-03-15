// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

contract XGrailWrapperStorage is Initializable {

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant _XGRAIL_SLOT = 0x97e71b30caa77601683af38d67cac22ff57e66336b454e50103498923d4dc5dc;
    bytes32 internal constant _CAMELOT_ROUTER_SLOT = 0xa6546e296eedb917361d302399881bcc9cfb6ce8241b2705afbd98c38a14e03d;
    bytes32 internal constant _YIELD_BOOSTER_SLOT = 0xbec2ddcc523ceccf38b524de8ba8b3f9263c108934a48e6c1382566b16a326d2;
    bytes32 internal constant _POTPOOL_SLOT = 0x7f4b50847e7d7a4da6a6ea36bfb188c77e9f093697337eb9a876744f926dd014;
    bytes32 internal constant _NEXT_IMPLEMENTATION_SLOT = 0xb1acf527cd7cd1668b30e5a9a1c0d845714604de29ce560150922c9d8c0937df;
    bytes32 internal constant _NEXT_IMPLEMENTATION_TIMESTAMP_SLOT = 0x3bc747f4b148b37be485de3223c90b4468252967d2ea7f9fcbd8b6e653f434c9;

    constructor() public {
        assert(_IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
        assert(_XGRAIL_SLOT == bytes32(uint256(keccak256("eip1967.vaultStorage.xGrail")) - 1));
        assert(_CAMELOT_ROUTER_SLOT == bytes32(uint256(keccak256("eip1967.vaultStorage.camelotRouter")) - 1));
        assert(_YIELD_BOOSTER_SLOT == bytes32(uint256(keccak256("eip1967.vaultStorage.yieldBooster")) - 1));
        assert(_POTPOOL_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.potPool")) - 1));
        assert(_NEXT_IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.vaultStorage.nextImplementation")) - 1));
        assert(_NEXT_IMPLEMENTATION_TIMESTAMP_SLOT == bytes32(uint256(keccak256("eip1967.vaultStorage.nextImplementationTimestamp")) - 1));
    }

    function initialize(
        address _xGrail,
        address _camelotRouter,
        address _yieldBooster,
        address _potPool
    ) public initializer {
        _setXGrail(_xGrail);
        _setCamelotRouter(_camelotRouter);
        _setYieldBooster(_yieldBooster);
        _setPotPool(_potPool);
    }

    function _setXGrail(address _address) internal {
        setAddress(_XGRAIL_SLOT, _address);
    }

    function _xGrail() internal view returns (address) {
        return getAddress(_XGRAIL_SLOT);
    }

    function _setCamelotRouter(address _address) internal {
        setAddress(_CAMELOT_ROUTER_SLOT, _address);
    }

    function _camelotRouter() internal view returns (address) {
        return getAddress(_CAMELOT_ROUTER_SLOT);
    }

    function _setYieldBooster(address _address) internal {
        setAddress(_YIELD_BOOSTER_SLOT, _address);
    }

    function _yieldBooster() internal view returns (address) {
        return getAddress(_YIELD_BOOSTER_SLOT);
    }

    function _setPotPool(address _address) internal {
        setAddress(_POTPOOL_SLOT, _address);
    }

    function _potPool() internal view returns (address) {
        return getAddress(_POTPOOL_SLOT);
    }

    function _setNextImplementation(address _address) internal {
        setAddress(_NEXT_IMPLEMENTATION_SLOT, _address);
    }

    function _nextImplementation() internal view returns (address) {
        return getAddress(_NEXT_IMPLEMENTATION_SLOT);
    }

    function _setNextImplementationTimestamp(uint256 _value) internal {
        setUint256(_NEXT_IMPLEMENTATION_TIMESTAMP_SLOT, _value);
    }

    function _nextImplementationTimestamp() internal view returns (uint256) {
        return getUint256(_NEXT_IMPLEMENTATION_TIMESTAMP_SLOT);
    }

    function _implementation() internal view returns (address) {
        return getAddress(_IMPLEMENTATION_SLOT);
    }

    function setBoolean(bytes32 slot, bool _value) internal {
        setUint256(slot, _value ? 1 : 0);
    }

    function getBoolean(bytes32 slot) internal view returns (bool) {
        return (getUint256(slot) == 1);
    }

    function setAddress(bytes32 slot, address _address) internal {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _address)
        }
    }

    function getAddress(bytes32 slot) internal view returns (address str) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            str := sload(slot)
        }
    }

    function setUint256(bytes32 slot, uint256 _value) internal {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _value)
        }
    }

    function getUint256(bytes32 slot) internal view returns (uint256 str) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            str := sload(slot)
        }
    }

    uint256[50] private ______gap;
}
