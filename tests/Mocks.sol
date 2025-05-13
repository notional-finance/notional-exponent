// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AbstractCustomOracle} from "../src/oracles/AbstractCustomOracle.sol";
import {AbstractYieldStrategy} from "../src/AbstractYieldStrategy.sol";

contract MockWrapperERC20 is ERC20 {
    ERC20 public token;
    uint256 public tokenPrecision;

    constructor(ERC20 _token) ERC20("MockWrapperERC20", "MWE") {
        token = _token;
        tokenPrecision = 10 ** token.decimals();
        _mint(msg.sender, 1000000 * 10e18);
    }

    function deposit(uint256 amount) public {
        token.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount * 1e18 / tokenPrecision);
    }

    function withdraw(uint256 amount) public {
        _burn(msg.sender, amount);
        token.transfer(msg.sender, amount * tokenPrecision / 1e18);
    }
}

contract MockOracle is AbstractCustomOracle {

    int256 public price;

    constructor(int256 _price) AbstractCustomOracle("MockOracle", address(0)) { price = _price; }

    function setPrice(int256 _price) public {
        price = _price;
    }

    function _calculateBaseToQuote() internal view override returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return (0, price, block.timestamp, block.timestamp, 0);
    }
}

contract MockYieldStrategy is AbstractYieldStrategy {
    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv
    ) AbstractYieldStrategy(_asset, _yieldToken, _feeRate, _irm, _lltv, ERC20(_yieldToken).decimals()) { }

    function _mintYieldTokens(uint256 assets, address /* receiver */, bytes memory /* depositData */) internal override {
        ERC20(asset).approve(address(yieldToken), type(uint256).max);
        MockWrapperERC20(yieldToken).deposit(assets);
    }

    function _redeemShares(uint256 sharesToRedeem, address /* sharesOwner */, uint256 /* sharesHeld */, bytes memory /* redeemData */) internal override returns (bool wasEscrowed) {
        uint256 yieldTokensBurned = convertSharesToYieldToken(sharesToRedeem);
        MockWrapperERC20(yieldToken).withdraw(yieldTokensBurned);
        wasEscrowed = false;
    }

    function _initiateWithdraw(address /* account */, uint256 /* yieldTokenAmount */, uint256 /* sharesHeld */, bytes memory /* data */) internal pure override returns (uint256 requestId) {
        requestId = 0;
    }
}
