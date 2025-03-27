// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

import {IYieldStrategy} from "./interfaces/IYieldStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract AbstractYieldStrategy is ERC20, IYieldStrategy {
    constructor(
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {}
}

