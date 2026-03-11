// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AsyncAbstractStakingStrategy } from "./AsyncAbstractStakingStrategy.sol";

contract CentrifugeStaking is AsyncAbstractStakingStrategy {
    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate
    )
        AsyncAbstractYieldStrategy(_asset, _yieldToken, _feeRate)
    { }

    function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal override {
        // TODO: how do I know which request id is being deposited?
        yieldToken.deposit(assets, address(this));
    }

    function _requestDeposit(
        uint256 assets,
        address receiver,
        bytes memory depositData
    )
        internal
        override
        returns (uint256 pendingAssets)
    {
        // TODO: i need a holder here....
        ERC20(asset).checkApprove(address(yieldToken), assets);
        uint256 requestId = yieldToken.requestDeposit(assets, address(this), depositData);
        pendingAssets = yieldToken.pendingDepositRequest(requestId, address(this));
    }
}
