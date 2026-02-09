// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { AbstractWithdrawRequestManager } from "./AbstractWithdrawRequestManager.sol";
import { ERC20, TokenUtils } from "../utils/TokenUtils.sol";
import { ClonedCoolDownHolder } from "./ClonedCoolDownHolder.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ADDRESS_REGISTRY, USDC } from "../utils/Constants.sol";

address constant iUSD = 0x48f9e38f3070AD8945DFEae3FA70987722E3D89c;

interface IGateway {
    function mintAndLock(address _to, uint256 _amount, uint32 _unwindingEpochs) external returns (uint256);
    function startUnwinding(uint256 _shares, uint32 _unwindingEpochs) external;
    function withdraw(uint256 _unwindingTimestamp) external;

    // NOTE: this is to get USDC from iUSD
    function redeem(address _to, uint256 _amount, uint256 _minAssetsOut) external returns (uint256);
    function claimRedemption() external;

    function getAddress(string memory _name) external view returns (address);
}

interface ILockingController {
    function shareToken(uint32 _unwindingEpochs) external view returns (address);
    function exchangeRate(uint32 _unwindingEpochs) external view returns (uint256);
    function unwindingModule() external view returns (address);
}

interface IUnwindingModule {
    struct UnwindingPosition {
        uint256 shares; // shares of receiptTokens of the position
        uint32 fromEpoch; // epoch when the position started unwinding
        uint32 toEpoch; // epoch when the position will end unwinding
        uint256 fromRewardWeight; // reward weight at the start of the unwinding
        uint256 rewardWeightDecrease; // reward weight decrease per epoch between fromEpoch and toEpoch
    }
    function positions(bytes32 id) external view returns (UnwindingPosition memory);
}

interface IRedeemController {
    function queueLength() external view returns (uint256);
    function userPendingClaims(address account) external view returns (uint256);
}

IGateway constant Gateway = IGateway(0x3f04b65Ddbd87f9CE0A2e7Eb24d80e7fb87625b5);

contract InfiniFiUnwindingHolder is ClonedCoolDownHolder {
    using TokenUtils for ERC20;

    uint256 internal constant EPOCH = 1 weeks;
    uint256 internal constant EPOCH_OFFSET = 3 days;

    address public immutable liUSD;
    uint32 public immutable UNWINDING_EPOCHS;

    uint40 public s_unwindingTimestamp;
    bool public s_hasCompletedUnwinding;
    bool public s_isInRedemptionQueue;

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
        ERC20(liUSD).checkApprove(address(Gateway), cooldownBalance);
        Gateway.startUnwinding(cooldownBalance, UNWINDING_EPOCHS);
        // This is required to recover the unwinding position.
        s_unwindingTimestamp = uint40(block.timestamp);
    }

    function unwindToUSDC() public {
        require(s_hasCompletedUnwinding == false);

        uint256 iUSDBefore = ERC20(iUSD).balanceOf(address(this));
        // We will receive iUSD as a result of the withdraw from the liUSD position.
        Gateway.withdraw(s_unwindingTimestamp);
        uint256 iUSDReceived = ERC20(iUSD).balanceOf(address(this)) - iUSDBefore;
        s_hasCompletedUnwinding = true;

        // Now we will trigger a redemption to USDC, this may or may not finalize immediately.
        IRedeemController redeemController = IRedeemController(Gateway.getAddress("redeemController"));
        // We can only tell if we are in the redemption queue by checking the queue length before and after
        // the redemption call. The queue information itself is not exposed in any interface.
        uint256 queueLengthBefore = redeemController.queueLength();
        ERC20(iUSD).checkApprove(address(Gateway), iUSDReceived);
        // We specify 0 minAssetsOut to ensure that if the redemption cannot finalize immediately we
        // will enter the redemption queue.
        Gateway.redeem(address(this), iUSDReceived, 0);
        uint256 queueLengthAfter = redeemController.queueLength();

        if (queueLengthAfter > queueLengthBefore) s_isInRedemptionQueue = true;
    }

    function _redemptionQueueClaims() internal view returns (uint256) {
        IRedeemController redeemController = IRedeemController(Gateway.getAddress("redeemController"));
        return redeemController.userPendingClaims(address(this));
    }

    function _finalizeCooldown() internal override returns (uint256 tokensClaimed, bool finalized) {
        if (!s_hasCompletedUnwinding) unwindToUSDC();
        if (s_isInRedemptionQueue) {
            uint256 pendingClaims = _redemptionQueueClaims();
            // We have to require this when in the redemption queue because this is only set after
            // the redemption has been processed.
            require(pendingClaims > 0, "No pending claims");
            Gateway.claimRedemption();
            s_isInRedemptionQueue = false;
        }

        tokensClaimed = USDC.balanceOf(address(this));
        USDC.transfer(manager, tokensClaimed);
        finalized = true;
    }

    function canFinalize() public view returns (bool) {
        if (!s_hasCompletedUnwinding) {
            // If the unwinding has not completed, check that the position has ended unwinding.
            IUnwindingModule unwindingModule =
                IUnwindingModule(ILockingController(Gateway.getAddress("lockingController")).unwindingModule());
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
        ILockingController lockingController = ILockingController(Gateway.getAddress("lockingController"));
        UNWINDING_EPOCHS = _unwindingEpochs;
        liUSD = _liUSD;
        // Ensure that these two are matching.
        require(lockingController.shareToken(UNWINDING_EPOCHS) == liUSD);
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
        ERC20(STAKING_TOKEN).checkApprove(address(Gateway), amount);
        Gateway.mintAndLock(address(this), amount, UNWINDING_EPOCHS);
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
        ILockingController lockingController = ILockingController(Gateway.getAddress("lockingController"));
        // This is reported in 18 decimals.
        uint256 exchangeRate = lockingController.exchangeRate(UNWINDING_EPOCHS);
        return exchangeRate * (10 ** TokenUtils.getDecimals(STAKING_TOKEN)) / 1e18;
    }
}
