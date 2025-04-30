// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {WETH9} from "../interfaces/IWETH.sol";

address constant ETH_ADDRESS = address(0);
WETH9 constant WETH = WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant ALT_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
uint256 constant CHAIN_ID_MAINNET = 1;
uint256 constant VAULT_SHARE_PRECISION = 1e18;
uint256 constant YEAR = 365 days;
