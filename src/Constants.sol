// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

address constant ETH_ADDRESS = address(0);

library TypeConvert {

    function toUint(int256 x) internal pure returns (uint256) {
        require(x >= 0);
        return uint256(x);
    }

    function toInt(uint256 x) internal pure returns (int256) {
        require (x <= uint256(type(int256).max)); // dev: toInt overflow
        return int256(x);
    }

}
