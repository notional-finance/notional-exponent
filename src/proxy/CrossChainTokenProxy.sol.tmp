// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

/// @notice Receives assets from a CrossChainYieldToken and then calls a withdraw request
/// manager to stake and withdraw assets.
contract CrossChainTokenProxy {
    IWithdrawRequestManager public immutable withdrawRequestManager;

    mapping(uint256 externalRequestId => uint256 requestId) public s_externalRequestIdToRequestId;

    modifier onlyBridgeContract() {
        require(msg.sender == bridgeContract);
        _;
    }

    function receiveAssetsAndStake(
        address account,
        address depositToken,
        uint256 amount,
        bytes calldata data
    )
        external
        onlyBridgeContract
    {
        ERC20(depositToken).checkApprove(address(withdrawRequestManager), amount);
        // Now this contract holds the yield tokens.
        uint256 yieldTokensMinted = withdrawRequestManager.stakeTokens(depositToken, amount, data);

        // Send a message back to the other chain with the account and the yield tokens minted so that
        // finalizeAssetStaking can be called.
        _sendMessageToChain(account, yieldTokensMinted);
    }

    function initiateWithdraw(
        address account,
        uint256 yieldTokenAmount,
        uint256 sharesAmount,
        bytes calldata data,
        address forceWithdrawFrom,
        uint256 externalRequestId
    )
        external
        onlyBridgeContract
    {
        IERC20(withdrawRequestManager.YIELD_TOKEN()).checkApprove(address(withdrawRequestManager), yieldTokenAmount);
        uint256 requestId =
            withdrawRequestManager.initiateWithdraw(account, yieldTokensMinted, sharesAmount, data, forceWithdrawFrom);
        // Map the external request id to the request id on this chain.
        s_externalRequestIdToRequestId[externalRequestId] = requestId;

        // No message is needed to be sent back to the other chain since the withdraw request manager will just wait
        // for the assets to be finalized on this chain.
    }

    function finalizeWithdrawRequest(address account) external {
        WithdrawRequest memory w = withdrawRequestManager.getWithdrawRequest(address(this), account);
        require(requestId != 0, "Invalid external request id");
        uint256 tokensWithdrawn =
            withdrawRequestManager.finalizeAndRedeemWithdrawRequest(account, w.yieldTokenAmount, w.sharesAmount);

        // Send a message back to the other chain with the tokens withdrawn so that
        // receiveWithdrawAssets can be called.
        _bridgeTokens(account, tokensWithdrawn);
    }
}
