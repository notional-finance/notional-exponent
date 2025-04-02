// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ETH_ADDRESS, ALT_ETH_ADDRESS} from "../Constants.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library TokenUtils {
    using SafeERC20 for IERC20;

    function getDecimals(address token) internal view returns (uint8 decimals) {
        decimals = (token == ETH_ADDRESS || token == ALT_ETH_ADDRESS) ?
            18 : ERC20(token).decimals();
        require(decimals <= 18);
    }

    function tokenBalance(address token) internal view returns (uint256) {
        return
            token == ETH_ADDRESS
                ? address(this).balance
                : ERC20(token).balanceOf(address(this));
    }

    function checkApprove(IERC20 token, address spender, uint256 amount) internal {
        if (address(token) == address(0)) return;

        IERC20(token).forceApprove(spender, amount);
    }

    function checkRevoke(IERC20 token, address spender) internal {
        if (address(token) == address(0)) return;
        IERC20(token).forceApprove(spender, 0);
    }
}