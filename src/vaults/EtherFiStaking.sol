// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.28;

contract EtherFiStaking is AbstractYieldStrategy {
    // Holds weETH, borrows WETH
    constructor(
        address _owner,
        uint256 _feeRate,
        address _irm,
        uint256 _lltv
    ) AbstractYieldStrategy(_owner, WETH, weETH, _feeRate, _irm, _lltv) { }

    function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal override returns (uint256 yieldTokensMinted) {
        (WithdrawRequest memory w, /* */) = IWithdrawRequestManager(withdrawRequestManager).getWithdrawRequest(address(this), receiver);
        require(w.requestId == 0, "Withdraw request already exists");

        uint256 eEthBalBefore = eETH.balanceOf(address(this));
        LiquidityPool.deposit{value: assets}();
        uint256 eETHMinted = eETH.balanceOf(address(this)) - eEthBalBefore;
        yieldTokensMinted = weETH.wrap(eETHMinted);
    }

    function _redeemYieldTokens(uint256 yieldTokensToRedeem, address sharesOwner, bytes memory redeemData) internal override {
        // TODO: trade out of it or go via withdraw request
    }

    function _postLiquidation(address liquidator, address liquidateAccount, uint256 sharesToLiquidator) internal override {
        // TODO: this may not be correct if shares and yield tokens are not 1:1
        IWithdrawRequestManager(withdrawRequestManager).splitWithdrawRequest(liquidator, liquidateAccount, sharesToLiquidator);
    }

    function convertYieldTokenToAsset() public view override returns (uint256 price) {
        // EtherFi valuation is always the oracle price
        return 0;
    }
}