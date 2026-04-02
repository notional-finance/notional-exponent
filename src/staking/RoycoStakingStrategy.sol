// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { StakingStrategy } from "./StakingStrategy.sol";
import { DepositParams, Trade, TradeType } from "./AbstractStakingStrategy.sol";
import { IConcreteWhitelistHook } from "../interfaces/IConcrete.sol";

contract RoycoStakingStrategy is StakingStrategy {
    constructor(address _asset, address _yieldToken, uint256 _feeRate)
        StakingStrategy(_asset, _yieldToken, _feeRate)
    { }

    function strategy() public pure override returns (string memory) {
        return "RoycoStaking";
    }

    function _checkRoycoAccount(address account) internal view {
        IConcreteWhitelistHook whitelistHook = IConcreteWhitelistHook(0x5c4952751CF5C9D4eA3ad84F3407C56Ba2342F13);
        require(whitelistHook.isWhitelisted(account));
    }

    function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal override {
        _checkRoycoAccount(receiver);
        if (depositData.length > 0) {
            // Allows for the yield token to be purchased from a pool when trading at a discount
            DepositParams memory params = abi.decode(depositData, (DepositParams));
            Trade memory trade = Trade({
                tradeType: TradeType.EXACT_IN_SINGLE,
                sellToken: address(asset),
                buyToken: address(yieldToken),
                amount: assets,
                limit: params.minPurchaseAmount,
                deadline: block.timestamp,
                exchangeData: params.exchangeData
            });
            _executeTrade(trade, params.dexId);
        } else {
            super._mintYieldTokens(assets, receiver, depositData);
        }
    }
}
