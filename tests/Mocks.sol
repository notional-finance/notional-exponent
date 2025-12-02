// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import { console } from "forge-std/src/console.sol";

import { IWithdrawRequestManager, WithdrawRequest } from "../src/interfaces/IWithdrawRequestManager.sol";
import { ADDRESS_REGISTRY } from "../src/utils/Constants.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AbstractCustomOracle } from "../src/oracles/AbstractCustomOracle.sol";
import { AbstractYieldStrategy } from "../src/AbstractYieldStrategy.sol";
import { RewardManagerMixin } from "../src/rewards/RewardManagerMixin.sol";
import { StakingStrategy } from "../src/staking/StakingStrategy.sol";

contract MockWrapperERC20 is ERC20 {
    ERC20 public token;
    uint256 public tokenPrecision;
    uint8 internal immutable _decimals;

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    constructor(ERC20 _token, uint8 decimals_) ERC20("MockWrapperERC20", "MWE") {
        token = _token;
        tokenPrecision = 10 ** token.decimals();
        _decimals = decimals_;

        uint256 precision = 10 ** _decimals;
        _mint(msg.sender, 1_000_000 * precision);
    }

    function deposit(uint256 amount) public {
        token.transferFrom(msg.sender, address(this), amount);
        uint256 precision = 10 ** _decimals;
        _mint(msg.sender, amount * precision / tokenPrecision);
    }

    function withdraw(uint256 amount) public {
        _burn(msg.sender, amount);
        uint256 precision = 10 ** _decimals;
        token.transfer(msg.sender, amount * tokenPrecision / precision);
    }
}

contract MockOracle is AbstractCustomOracle {
    int256 public price;

    constructor(int256 _price) AbstractCustomOracle("MockOracle", address(0)) {
        price = _price;
    }

    function setPrice(int256 _price) public {
        price = _price;
    }

    function _calculateBaseToQuote()
        internal
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, price, block.timestamp, block.timestamp, 0);
    }
}

contract MockYieldStrategy is AbstractYieldStrategy {
    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate
    )
        AbstractYieldStrategy(_asset, _yieldToken, _feeRate, ERC20(_yieldToken).decimals())
    { }

    function _mintYieldTokens(
        uint256 assets,
        address, /* receiver */
        bytes memory /* depositData */
    )
        internal
        override
    {
        ERC20(asset).approve(address(yieldToken), type(uint256).max);
        MockWrapperERC20(yieldToken).deposit(assets);
    }

    function _redeemShares(
        uint256 sharesToRedeem,
        address, /* sharesOwner */
        bool, /* isEscrowed */
        bytes memory /* redeemData */
    )
        internal
        override
    {
        uint256 yieldTokensBurned = convertSharesToYieldToken(sharesToRedeem);
        MockWrapperERC20(yieldToken).withdraw(yieldTokensBurned);
    }

    function _initiateWithdraw(
        address, /* account */
        uint256, /* yieldTokenAmount */
        uint256, /* sharesHeld */
        bytes memory, /* data */
        address /* forceWithdrawFrom */
    )
        internal
        pure
        override
        returns (uint256 requestId)
    {
        requestId = 0;
    }

    function _postLiquidation(
        address, /* liquidator */
        address, /* liquidateAccount */
        uint256 /* sharesToLiquidator */
    )
        internal
        pure
        override
        returns (bool didTokenize)
    {
        didTokenize = false;
    }

    function _preLiquidation(
        address, /* liquidateAccount */
        address, /* liquidator */
        uint256, /* sharesToLiquidate */
        uint256 /* accountSharesHeld */
    )
        internal
        pure
        override
    {
        // No-op
    }

    function transientVariables() external view returns (address, address, address, uint256) {
        return (t_CurrentAccount, t_CurrentLendingRouter, t_AllowTransfer_To, t_AllowTransfer_Amount);
    }

    function strategy() public pure override returns (string memory) {
        return "MockYieldStrategy";
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1_000_000e18);
    }
}

contract MockRewardPool is ERC20 {
    uint256 public rewardAmount;
    ERC20 public immutable depositToken;
    ERC20 public immutable rewardToken;

    constructor(address _depositToken) ERC20("MockRewardPool", "MRP") {
        depositToken = ERC20(_depositToken);
        rewardToken = new MockERC20("MockRewardToken", "MRT");
    }

    function setRewardAmount(uint256 amount) external {
        rewardAmount = amount;
    }

    function getReward(address holder, bool claim) external returns (bool) {
        if (rewardAmount == 0) return true;
        if (claim) rewardToken.transfer(holder, rewardAmount);
        // Clear the reward amount every time it's claimed
        rewardAmount = 0;
        return true;
    }

    function deposit(
        uint256,
        /* poolId */
        uint256 amount,
        bool /* stake */
    )
        external
        returns (bool success)
    {
        depositToken.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount * 1e18 / 1e6);
        success = true;
    }

    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool success) {
        if (claim) rewardToken.transfer(address(this), amount);
        _burn(msg.sender, amount);
        depositToken.transfer(msg.sender, amount * 1e6 / 1e18);
        success = true;
    }

    function pid() external pure returns (uint256) {
        return 0;
    }

    function operator() external view returns (address) {
        return address(this);
    }
}

contract MockRewardVault is RewardManagerMixin {
    constructor(
        address _asset,
        address _yieldToken,
        uint256 _feeRate,
        address _rewardManager
    )
        RewardManagerMixin(_asset, _yieldToken, _feeRate, _rewardManager, ERC20(_yieldToken).decimals())
    {
        withdrawRequestManager = IWithdrawRequestManager(ADDRESS_REGISTRY.getWithdrawRequestManager(_yieldToken));
    }

    function strategy() public pure override returns (string memory) {
        return "MockRewardVault";
    }

    function _mintYieldTokens(
        uint256 assets,
        address, /* receiver */
        bytes memory /* depositData */
    )
        internal
        override
    {
        ERC20(asset).approve(address(yieldToken), type(uint256).max);
        MockRewardPool(yieldToken).deposit(0, assets, true);
    }

    function _redeemShares(
        uint256 sharesToRedeem,
        address sharesOwner,
        bool isEscrowed,
        bytes memory /* redeemData */
    )
        internal
        override
    {
        if (isEscrowed) {
            (
                WithdrawRequest memory w, /* */
            ) = withdrawRequestManager.getWithdrawRequest(address(this), sharesOwner);

            if (w.requestId != 0) {
                uint256 yieldTokenAmount = w.yieldTokenAmount * sharesToRedeem / w.sharesAmount;
                uint256 tokensWithdrawn = withdrawRequestManager.finalizeAndRedeemWithdrawRequest(
                    sharesOwner, yieldTokenAmount, sharesToRedeem
                );
                MockRewardPool(yieldToken).withdrawAndUnwrap(tokensWithdrawn, true);
            }
        } else {
            uint256 yieldTokensBurned = convertSharesToYieldToken(sharesToRedeem);
            MockRewardPool(yieldToken).withdrawAndUnwrap(yieldTokensBurned, true);
        }
    }

    function __initiateWithdraw(
        address account,
        uint256 yieldTokenAmount,
        uint256 sharesHeld,
        bytes memory data,
        address forceWithdrawFrom
    )
        internal
        override
        returns (uint256 requestId)
    {
        ERC20(yieldToken).approve(address(withdrawRequestManager), yieldTokenAmount);
        requestId =
            withdrawRequestManager.initiateWithdraw(account, yieldTokenAmount, sharesHeld, data, forceWithdrawFrom);
    }

    function __postLiquidation(
        address liquidator,
        address liquidateAccount,
        uint256 sharesToLiquidator
    )
        internal
        override
        returns (bool didTokenize)
    {
        if (address(withdrawRequestManager) != address(0)) {
            // No need to accrue fees because neither the total supply or total yield token balance is changing. If
            // there
            // is no withdraw request then this will be a noop.
            didTokenize =
                withdrawRequestManager.tokenizeWithdrawRequest(liquidateAccount, liquidator, sharesToLiquidator);
        }
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        if (t_CurrentAccount != address(0) && address(withdrawRequestManager) != address(0)) {
            (bool hasRequest, uint256 value) =
                withdrawRequestManager.getWithdrawRequestValue(address(this), t_CurrentAccount, asset, shares);
            // If the account does not have a withdraw request then this will fall through
            // to the super implementation.
            if (hasRequest) return value;
        }

        return super.convertToAssets(shares);
    }
}

contract MockStakingStrategy is StakingStrategy {
    constructor(address _asset, address _yieldToken, uint256 _feeRate)
        StakingStrategy(_asset, _yieldToken, _feeRate)
    { }

    function transientVariables() external view returns (address, address, address, uint256) {
        return (t_CurrentAccount, t_CurrentLendingRouter, t_AllowTransfer_To, t_AllowTransfer_Amount);
    }
}
