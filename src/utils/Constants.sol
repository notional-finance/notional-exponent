// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { WETH9 } from "../interfaces/IWETH.sol";
import { AddressRegistry } from "../proxy/AddressRegistry.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

address constant ETH_ADDRESS = address(0);
ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
address constant ALT_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
uint256 constant DEFAULT_PRECISION = 1e18;
uint256 constant DEFAULT_DECIMALS = 18;
uint256 constant SHARE_PRECISION = 1e24;
uint256 constant VIRTUAL_SHARES = 1e6;

uint256 constant COOLDOWN_PERIOD = 5 minutes;
uint256 constant YEAR = 365 days;

// Will move these to a deployment file when we go to multiple chains
uint256 constant CHAIN_ID_MAINNET = 1;
WETH9 constant WETH = WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
AddressRegistry constant ADDRESS_REGISTRY = AddressRegistry(0xe335d314BD4eF7DD44F103dC124FEFb7Ce63eC95);
TimelockController constant TIMELOCK_CONTROLLER =
    TimelockController(payable(0x375eaFe4348c6aA851cdfa5f84eC268f73643235));
