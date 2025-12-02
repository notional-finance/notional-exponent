// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.28;

import { WETH9 } from "../../interfaces/IWETH.sol";
import { ISwapRouter } from "../adapters/UniV3Adapter.sol";
import { ICurveRouterV2 } from "../../interfaces/Curve/ICurve.sol";
import { ITradingModule } from "../../interfaces/ITradingModule.sol";
import { AggregatorV2V3Interface } from "../../interfaces/AggregatorV2V3Interface.sol";

/// @title Hardcoded Deployment Addresses for Mainnet
library Deployments {
    uint256 internal constant CHAIN_ID = 1;
    address internal constant ETH_ADDRESS = address(0);
    WETH9 internal constant WETH = WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ISwapRouter internal constant UNIV3_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address internal constant ZERO_EX = 0x0000000000001fF3684f28c67538d4D072C22734;

    address internal constant ALT_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    ICurveRouterV2 public constant CURVE_ROUTER_V2 = ICurveRouterV2(0xF0d4c12A5768D806021F80a262B4d39d26C58b8D);

    ITradingModule internal constant TRADING_MODULE = ITradingModule(0x594734c7e06C3D483466ADBCe401C6Bd269746C8);

    // Chainlink L2 Sequencer Uptime: https://docs.chain.link/data-feeds/l2-sequencer-feeds/
    AggregatorV2V3Interface internal constant SEQUENCER_UPTIME_ORACLE = AggregatorV2V3Interface(address(0));
}
