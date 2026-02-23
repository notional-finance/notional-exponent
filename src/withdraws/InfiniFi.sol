// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractWithdrawRequestManager } from "./AbstractWithdrawRequestManager.sol";
import { ERC20, TokenUtils } from "../utils/TokenUtils.sol";
import { ClonedCoolDownHolder } from "./ClonedCoolDownHolder.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ADDRESS_REGISTRY, USDC } from "../utils/Constants.sol";
import {
    INFINIFI_GATEWAY,
    iUSD,
    IRedeemController,
    IUnwindingModule,
    ILockingController
} from "../interfaces/IInfiniFi.sol";

contract InfiniFiUnwindingHolder is ClonedCoolDownHolder {
    using TokenUtils for ERC20;

    uint256 internal constant EPOCH = 1 weeks;
    uint256 internal constant EPOCH_OFFSET = 3 days;

    address public immutable liUSD;
    uint32 public immutable UNWINDING_EPOCHS;

    uint40 public s_unwindingTimestamp;
    bool public s_hasCompletedUnwinding;
    bool public s_isInRedemptionQueue;
    uint128 public s_iUSDCooldownAmount;

    constructor(address _manager, address _liUSD, uint32 _unwindingEpochs) ClonedCoolDownHolder(_manager) {
        liUSD = _liUSD;
        UNWINDING_EPOCHS = _unwindingEpochs;
    }

    function _stopCooldown() internal pure override {
        // NOTE: it is possible to stop a cool down in InfiniFi, but we do not
        // support it here.
        revert();
    }

    function _startCooldown(uint256 cooldownBalance) internal override {
        ERC20(liUSD).checkApprove(address(INFINIFI_GATEWAY), cooldownBalance);
        if (UNWINDING_EPOCHS > 0) {
            INFINIFI_GATEWAY.startUnwinding(cooldownBalance, UNWINDING_EPOCHS);
            // This is required to recover the unwinding position.
            s_unwindingTimestamp = uint40(block.timestamp);
        } else {
            // If we are using siUSD then we can just unwind to USDC directly. If the iUSD
            // redemption is processed immediately then we can finalize the cooldown immediately.
            unwindToUSDC();
        }
    }

    function unwindToUSDC() public {
        require(s_hasCompletedUnwinding == false);

        uint256 iUSDBefore = ERC20(iUSD).balanceOf(address(this));
        if (UNWINDING_EPOCHS > 0) {
            // We will receive iUSD as a result of the withdraw from the liUSD position.
            INFINIFI_GATEWAY.withdraw(s_unwindingTimestamp);
        } else {
            // Unstake the total siUSD balance directly.
            INFINIFI_GATEWAY.unstake(address(this), ERC20(liUSD).balanceOf(address(this)));
        }
        uint256 iUSDReceived = ERC20(iUSD).balanceOf(address(this)) - iUSDBefore;
        s_hasCompletedUnwinding = true;

        // Now we will trigger a redemption to USDC, this may or may not finalize immediately.
        IRedeemController redeemController = IRedeemController(INFINIFI_GATEWAY.getAddress("redeemController"));
        // We can only tell if we are in the redemption queue by checking the queue length before and after
        // the redemption call. The queue information itself is not exposed in any interface.
        uint256 queueLengthBefore = redeemController.queueLength();
        ERC20(iUSD).checkApprove(address(INFINIFI_GATEWAY), iUSDReceived);
        // We specify 0 minAssetsOut to ensure that if the redemption cannot finalize immediately we
        // will enter the redemption queue.
        INFINIFI_GATEWAY.redeem(address(this), iUSDReceived, 0);
        uint256 queueLengthAfter = redeemController.queueLength();

        if (queueLengthAfter > queueLengthBefore) {
            s_isInRedemptionQueue = true;
            // This is used as a heuristic to ensure that the user does not end up
            // in a partial redemption state.
            s_iUSDCooldownAmount = uint128(iUSDReceived);
        }
    }

    function _redemptionQueueClaims() internal view returns (uint256) {
        IRedeemController redeemController = IRedeemController(INFINIFI_GATEWAY.getAddress("redeemController"));
        return redeemController.userPendingClaims(address(this));
    }

    function claimRedemption() public {
        require(s_isInRedemptionQueue);
        uint256 pendingClaims = _redemptionQueueClaims();
        // We have to require this when in the redemption queue because this is only set after
        // the redemption has been processed.
        require(pendingClaims > 0, "No pending claims");
        INFINIFI_GATEWAY.claimRedemption();

        // It is possible that the pendingClaims is not the full amount of USDC that the user
        // is entitled to if InfiniFi has processed their redemption only partially. We are unable to
        // directly read the queue from a smart contract so we check that the balance of USDC is 1-1
        // with the initial iUSD amount. If it is lower, then we allow the user to re-claim their redemption
        // or an admin to clear the s_isInRedemptionQueue flag in the case that the partial redemption will
        // never be processed.
        uint256 expectedUSDC = s_iUSDCooldownAmount * 1e6 / 1e18;
        if (USDC.balanceOf(address(this)) >= expectedUSDC) {
            s_isInRedemptionQueue = false;
        }
    }

    function clearRedemptionQueue() public {
        // Allow the admin to clear the redemption queue in the case that the partial redemption will
        // never be processed. This will allow the user to finalize their cooldown with whatever funds
        // are left available.
        require(msg.sender == ADDRESS_REGISTRY.upgradeAdmin());
        claimRedemption();
        s_isInRedemptionQueue = false;
    }

    function _finalizeCooldown() internal override returns (uint256 tokensClaimed, bool finalized) {
        if (!s_hasCompletedUnwinding) unwindToUSDC();
        if (s_isInRedemptionQueue) claimRedemption();
        // Check that we are no longer in the redemption queue, this can happen if the
        // claimRedemption() call results in a partial redemption.
        if (s_isInRedemptionQueue) revert("Redemption Queue");

        tokensClaimed = USDC.balanceOf(address(this));
        USDC.transfer(manager, tokensClaimed);
        finalized = true;
    }

    function canFinalize() public view returns (bool) {
        if (!s_hasCompletedUnwinding) {
            // If the unwinding has not completed, check that the position has ended unwinding.
            IUnwindingModule unwindingModule = IUnwindingModule(
                ILockingController(INFINIFI_GATEWAY.getAddress("lockingController")).unwindingModule()
            );
            IUnwindingModule.UnwindingPosition memory position =
                unwindingModule.positions(keccak256(abi.encode(address(this), s_unwindingTimestamp)));
            uint256 currentEpoch = (block.timestamp - EPOCH_OFFSET) / EPOCH;

            return currentEpoch >= position.toEpoch;
        } else {
            if (s_isInRedemptionQueue) return _redemptionQueueClaims() > 0;
            // If we are not in the redemption queue and the unwinding has completed,
            // then the cooldown can be finalized immediately. This would happen if someone
            // called unwindToUSDC() before the cooldown was finalized.
            return true;
        }
    }
}

contract InfiniFiWithdrawRequestManager is AbstractWithdrawRequestManager {
    using TokenUtils for ERC20;

    address public immutable liUSD;
    uint32 public immutable UNWINDING_EPOCHS;
    address public HOLDER_IMPLEMENTATION;

    constructor(
        address _liUSD,
        uint32 _unwindingEpochs
    )
        AbstractWithdrawRequestManager(address(USDC), _liUSD, address(USDC))
    {
        if (_unwindingEpochs > 0) {
            ILockingController lockingController = ILockingController(INFINIFI_GATEWAY.getAddress("lockingController"));
            UNWINDING_EPOCHS = _unwindingEpochs;
            liUSD = _liUSD;
            // Ensure that these two are matching.
            require(lockingController.shareToken(UNWINDING_EPOCHS) == liUSD);
        } else {
            // In this case we are using siUSD which has no unwinding epochs.
            liUSD = INFINIFI_GATEWAY.getAddress("stakedToken");
            UNWINDING_EPOCHS = 0;
            require(liUSD == _liUSD);
        }
    }

    function _initialize(
        bytes calldata /* data */
    )
        internal
        override
    {
        HOLDER_IMPLEMENTATION = address(new InfiniFiUnwindingHolder(address(this), liUSD, UNWINDING_EPOCHS));
    }

    function redeployHolder() external {
        require(msg.sender == ADDRESS_REGISTRY.upgradeAdmin());
        HOLDER_IMPLEMENTATION = address(new InfiniFiUnwindingHolder(address(this), liUSD, UNWINDING_EPOCHS));
    }

    function _stakeTokens(
        uint256 amount,
        bytes memory /* stakeData */
    )
        internal
        override
    {
        ERC20(STAKING_TOKEN).checkApprove(address(INFINIFI_GATEWAY), amount);
        if (UNWINDING_EPOCHS > 0) {
            INFINIFI_GATEWAY.mintAndLock(address(this), amount, UNWINDING_EPOCHS);
        } else {
            INFINIFI_GATEWAY.mintAndStake(address(this), amount);
        }
    }

    function _initiateWithdrawImpl(
        address, /* account */
        uint256 amountToWithdraw,
        bytes calldata, /* data */
        address /* forceWithdrawFrom */
    )
        internal
        override
        returns (uint256 requestId)
    {
        InfiniFiUnwindingHolder holder = InfiniFiUnwindingHolder(payable(Clones.clone(HOLDER_IMPLEMENTATION)));
        ERC20(liUSD).transfer(address(holder), amountToWithdraw);
        holder.startCooldown(amountToWithdraw);

        return uint256(uint160(address(holder)));
    }

    function _finalizeWithdrawImpl(
        address, /* account */
        uint256 requestId
    )
        internal
        override
        returns (uint256 tokensClaimed)
    {
        InfiniFiUnwindingHolder holder = InfiniFiUnwindingHolder(address(uint160(requestId)));
        bool finalized;
        (tokensClaimed, finalized) = holder.finalizeCooldown();
        require(finalized);
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view override returns (bool) {
        InfiniFiUnwindingHolder holder = InfiniFiUnwindingHolder(address(uint160(requestId)));
        return holder.canFinalize();
    }

    function getExchangeRate() public view override returns (uint256) {
        if (UNWINDING_EPOCHS > 0) {
            ILockingController lockingController = ILockingController(INFINIFI_GATEWAY.getAddress("lockingController"));
            // This is reported in 18 decimals.
            uint256 exchangeRate = lockingController.exchangeRate(UNWINDING_EPOCHS);
            return exchangeRate * (10 ** TokenUtils.getDecimals(STAKING_TOKEN)) / 1e18;
        } else {
            // If we are using siUSD then it implements the ERC4626 interface,
            // so the super implementation will return the correct exchange rate.
            return super.getExchangeRate();
        }
    }
}
