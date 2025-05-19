// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {ClonedCoolDownHolder} from "./ClonedCoolDownHolder.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AbstractWithdrawRequestManager} from "./AbstractWithdrawRequestManager.sol";
import {TypeConvert} from "../utils/TypeConvert.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

// Mainnet Ethena contract addresses
IsUSDe constant sUSDe = IsUSDe(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
ERC20 constant USDe = ERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);
// Dai and sDAI are required for trading out of sUSDe
ERC20 constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
IERC4626 constant sDAI = IERC4626(0x83F20F44975D03b1b09e64809B757c47f942BEeA);

interface IsUSDe is IERC4626 {
    struct UserCooldown {
        uint104 cooldownEnd;
        uint152 underlyingAmount;
    }

    function cooldownDuration() external view returns (uint24);
    function cooldowns(address account) external view returns (UserCooldown memory);
    function cooldownShares(uint256 shares) external returns (uint256 assets);
    function unstake(address receiver) external;
}


contract EthenaCooldownHolder is ClonedCoolDownHolder {

    constructor(address _manager) ClonedCoolDownHolder(_manager) { }

    /// @notice There is no way to stop a cool down
    function _stopCooldown() internal pure override { revert(); }

    function _startCooldown(uint256 cooldownBalance) internal override {
        uint24 duration = sUSDe.cooldownDuration();
        if (duration == 0) {
            // If the cooldown duration is set to zero, can redeem immediately
            sUSDe.redeem(cooldownBalance, address(this), address(this));
        } else {
            // If we execute a second cooldown while one exists, the cooldown end
            // will be pushed further out. This holder should only ever have one
            // cooldown ever.
            require(sUSDe.cooldowns(address(this)).cooldownEnd == 0);
            sUSDe.cooldownShares(cooldownBalance);
        }
    }

    function _finalizeCooldown() internal override returns (uint256 tokensClaimed, bool finalized) {
        uint24 duration = sUSDe.cooldownDuration();
        IsUSDe.UserCooldown memory userCooldown = sUSDe.cooldowns(address(this));

        if (block.timestamp < userCooldown.cooldownEnd && 0 < duration) {
            // Cooldown has not completed, return a false for finalized
            return (0, false);
        }

        uint256 balanceBefore = USDe.balanceOf(address(this));
        // If a cooldown has been initiated, need to call unstake to complete it. If
        // duration was set to zero then the USDe will be on this contract already.
        if (0 < userCooldown.cooldownEnd) sUSDe.unstake(address(this));
        uint256 balanceAfter = USDe.balanceOf(address(this));

        // USDe is immutable. It cannot have a transfer tax and it is ERC20 compliant
        // so we do not need to use the additional protections here.
        tokensClaimed = balanceAfter - balanceBefore;
        USDe.transfer(manager, tokensClaimed);
        finalized = true;
    }
}

contract EthenaWithdrawRequestManager is AbstractWithdrawRequestManager {
    using TypeConvert for int256;

    address internal immutable HOLDER_IMPLEMENTATION;
    uint256 internal constant USDE_PRECISION = 1e18;

    constructor() AbstractWithdrawRequestManager(address(USDe), address(sUSDe), address(USDe)) {
        HOLDER_IMPLEMENTATION = address(new EthenaCooldownHolder(address(this)));
    }

    function _stakeTokens(
        uint256 usdeAmount,
        bytes memory /* stakeData */
    ) internal override {
        USDe.approve(address(sUSDe), usdeAmount);
        sUSDe.deposit(usdeAmount, address(this));
    }

    function _initiateWithdrawImpl(
        address /* account */,
        uint256 balanceToTransfer,
        bytes calldata /* data */
    ) internal override returns (uint256 requestId) {
        EthenaCooldownHolder holder = EthenaCooldownHolder(Clones.clone(HOLDER_IMPLEMENTATION));
        sUSDe.transfer(address(holder), balanceToTransfer);
        holder.startCooldown(balanceToTransfer);

        return uint256(uint160(address(holder)));
    }

    function _finalizeWithdrawImpl(
        address /* account */,
        uint256 requestId
    ) internal override returns (uint256 tokensClaimed, bool finalized) {
        EthenaCooldownHolder holder = EthenaCooldownHolder(address(uint160(requestId)));
        (tokensClaimed, finalized) = holder.finalizeCooldown();
    }

    function canFinalizeWithdrawRequest(uint256 requestId) public view override returns (bool) {
        uint24 duration = sUSDe.cooldownDuration();
        address holder = address(uint160(requestId));
        // This valuation is the amount of USDe the account will receive at cooldown, once
        // a cooldown is initiated the account is no longer receiving sUSDe yield. This balance
        // of USDe is transferred to a Silo contract and guaranteed to be available once the
        // cooldown has passed.
        IsUSDe.UserCooldown memory userCooldown = sUSDe.cooldowns(holder);
        return (userCooldown.cooldownEnd < block.timestamp || 0 == duration);
    }

}
