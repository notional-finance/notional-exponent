// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {ILendingRouter} from "../interfaces/ILendingRouter.sol";
import {
    NotAuthorized,
    CannotExitPositionWithinCooldownPeriod,
    CannotInitiateWithdraw,
    CannotForceWithdraw
} from "../interfaces/Errors.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRewardManager} from "../interfaces/IRewardManager.sol";
import {IYieldStrategy} from "../interfaces/IYieldStrategy.sol";
import {ILendingRouter} from "../interfaces/ILendingRouter.sol";
import {ADDRESS_REGISTRY, COOLDOWN_PERIOD} from "../utils/Constants.sol";

struct MigrateParams {
    address fromLendingRouter;
    uint256 sharesToMigrate;
    uint256 assetToRepay;
}

abstract contract AbstractLendingRouter is ILendingRouter {
    using SafeERC20 for ERC20;

    mapping(address user => mapping(address operator => bool approved)) private s_isApproved;
    mapping(address vault => mapping(address user => uint256 lastEntryTime)) internal s_lastEntryTime;

    /*** Authorization Methods ***/
    modifier isAuthorized(address onBehalf) {
        // In this case msg.sender is the operator
        if (msg.sender != onBehalf && !isApproved(onBehalf, msg.sender)) {
            revert NotAuthorized(msg.sender, onBehalf);
        }

        _;
    }

    function setApproval(address operator, bool approved) external override {
        if (operator == msg.sender) revert NotAuthorized(msg.sender, operator);
        s_isApproved[msg.sender][operator] = approved;
    }

    function isApproved(address user, address operator) public view override returns (bool) {
        return s_isApproved[user][operator];
    }

    function enterPosition(
        address onBehalf,
        address vault,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes calldata depositData
    ) external override {
        // Is authorized is checked in this call
        enterPosition(onBehalf, vault, depositAssetAmount, borrowAmount, depositData, bytes(""));
    }

    function enterPosition(
        address onBehalf,
        address vault,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes calldata depositData,
        bytes memory migrateData
    ) public override isAuthorized(onBehalf) {
        address asset = IYieldStrategy(vault).asset();

        if (depositAssetAmount > 0) {
            ERC20(asset).safeTransferFrom(msg.sender, address(this), depositAssetAmount);
        }

        // TODO: if migrate data is set and we have a max repay how do we get the borrow amount?
        if (borrowAmount > 0) {
            _flashBorrowAndEnter(
                onBehalf, vault, asset, depositAssetAmount, borrowAmount, depositData, migrateData
            );
        } else {
            _enterOrMigrate(
                onBehalf, vault, asset, depositAssetAmount, depositData, migrateData
            );
        }

        s_lastEntryTime[vault][onBehalf] = block.timestamp;
    }

    function exitPosition(
        address onBehalf,
        address vault,
        address receiver,
        uint256 sharesToRedeem,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) external override isAuthorized(onBehalf) {
        if (block.timestamp - s_lastEntryTime[vault][onBehalf] < COOLDOWN_PERIOD) {
            revert CannotExitPositionWithinCooldownPeriod();
        }

        address asset = IYieldStrategy(vault).asset();
        if (0 < assetToRepay) {
            _exitWithRepay(onBehalf, vault, asset, receiver, sharesToRedeem, assetToRepay, redeemData);
        } else {
            address migrateTo = _isMigrate(receiver) ? receiver : address(0);
            uint256 assetsWithdrawn = _redeemShares(onBehalf, vault, asset, migrateTo, sharesToRedeem, redeemData);
            if (0 < assetsWithdrawn) ERC20(asset).safeTransfer(receiver, assetsWithdrawn);
        }
    }

    function liquidate(
        address liquidateAccount,
        address vault,
        uint256 seizedAssets,
        uint256 repaidShares
    ) external override returns (uint256 sharesToLiquidator) {
        address liquidator = msg.sender;
        // If the liquidator has a position then they cannot liquidate or they will have
        // a native balance and a balance on the lending market.
        require(balanceOfCollateral(liquidator, vault) == 0);

        IYieldStrategy(vault).preLiquidation(
            liquidator, liquidateAccount, seizedAssets, balanceOfCollateral(liquidateAccount, vault)
        );

        sharesToLiquidator = _liquidate(liquidator, vault, liquidateAccount, seizedAssets, repaidShares);

        IYieldStrategy(vault).postLiquidation(liquidator, liquidateAccount, sharesToLiquidator);

        // The liquidator will receive shares in their native balance and then they can call redeem
        // on the yield strategy to get the assets.
    }

    function _isMigrate(address receiver) internal view returns (bool) {
        return receiver == msg.sender && ADDRESS_REGISTRY.isLendingRouter(msg.sender);
    }

    function _enterOrMigrate(
        address onBehalf,
        address vault,
        address asset,
        uint256 assetAmount,
        bytes memory depositData,
        bytes memory migrateData
    ) internal returns (uint256 sharesReceived) {
        if (0 < migrateData.length) {
            MigrateParams memory migrateParams = abi.decode(migrateData, (MigrateParams));
            require(ADDRESS_REGISTRY.isLendingRouter(migrateParams.fromLendingRouter), "Invalid lending router");

            // Allow the previous lending router to repay the debt from assets held here.
            ERC20(asset).approve(migrateParams.fromLendingRouter, migrateParams.assetToRepay);
            // On migrate the receiver is this current lending router
            ILendingRouter(migrateParams.fromLendingRouter).exitPosition(
                onBehalf, vault, address(this), migrateParams.sharesToMigrate, migrateParams.assetToRepay, bytes("")
            );
            sharesReceived = migrateParams.sharesToMigrate;
            // TODO: is this vulnerable to donation attack?
            assetAmount = ERC20(asset).balanceOf(address(this));
        }

        if (0 < assetAmount) {
            ERC20(asset).approve(vault, assetAmount);
            sharesReceived += IYieldStrategy(vault).mintShares(
                assetAmount, onBehalf, depositData
            );
        }

        _supplyCollateral(onBehalf, vault, asset, sharesReceived);
    }

    function _redeemShares(
        address sharesOwner,
        address vault,
        address asset,
        address migrateTo,
        uint256 sharesToRedeem,
        bytes memory redeemData
    ) internal returns (uint256 assetsWithdrawn) {
        address receiver;
        uint256 balanceBefore;
        if (migrateTo == address(0)) {
            receiver = sharesOwner;
            balanceBefore = balanceOfCollateral(sharesOwner, vault);
        } else {
            // If we are migrating shares then we need to transfer them to the new lending router and
            // we do not need to track the balance before.
            receiver = migrateTo;
        }

        // Allows the transfer from the lending market to the sharesOwner
        IYieldStrategy(vault).allowTransfer(receiver, sharesToRedeem);

        _withdrawCollateral(vault, asset, sharesToRedeem, sharesOwner, receiver);

        // If we are not migrating then burn the shares
        if (migrateTo == address(0)) {
            assetsWithdrawn = IYieldStrategy(vault).burnShares(
                sharesOwner, sharesToRedeem, balanceBefore, redeemData
            );
        }
    }

    function _flashBorrowAndEnter(
        address onBehalf,
        address vault,
        address asset,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes calldata depositData,
        bytes memory migrateData
    ) internal virtual;

    function _supplyCollateral(
        address onBehalf, address vault, address asset, uint256 sharesReceived
    ) internal virtual;

    function _liquidate(
        address liquidator,
        address vault,
        address liquidateAccount,
        uint256 seizedAssets,
        uint256 repaidShares
    ) internal virtual returns (uint256 sharesToLiquidator);

    function _withdrawCollateral(
        address vault,
        address asset,
        uint256 sharesToRedeem,
        address sharesOwner,
        address receiver
    ) internal virtual;

    function _exitWithRepay(
        address onBehalf,
        address vault,
        address asset,
        address receiver,
        uint256 sharesToRedeem,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) internal virtual;

    function healthFactor(address borrower, address vault) public override virtual returns (uint256 borrowed, uint256 collateralValue, uint256 maxBorrow);

    function balanceOfCollateral(address account, address vault) public override view virtual returns (uint256 collateralBalance);


    function initiateWithdraw(address vault, bytes calldata data) external returns (uint256 requestId) {
        requestId = _initiateWithdraw(vault, msg.sender, data);

        // Can only initiate a withdraw if health factor remains positive
        (uint256 borrowed, /* */, uint256 maxBorrow) = healthFactor(msg.sender, vault);
        if (borrowed > maxBorrow) revert CannotInitiateWithdraw(msg.sender);
    }

    function forceWithdraw(address vault, address account, bytes calldata data) external returns (uint256 requestId) {
        // Can only force a withdraw if health factor is negative, this allows a liquidator to
        // force a withdraw and liquidate a position at a later time.
        (uint256 borrowed, /* */, uint256 maxBorrow) = healthFactor(account, vault);
        if (borrowed <= maxBorrow) revert CannotForceWithdraw(account);

        requestId = _initiateWithdraw(vault, account, data);
    }

    function claimRewards(address vault) external returns (uint256[] memory rewards) {
        return IRewardManager(vault).claimAccountRewards(msg.sender, balanceOfCollateral(msg.sender, vault));
    }

    function _initiateWithdraw(
        address vault,
        address account,
        bytes calldata data
    ) internal returns (uint256 requestId) {
        uint256 sharesHeld = balanceOfCollateral(account, vault);
        return IYieldStrategy(vault).initiateWithdraw(account, sharesHeld, data);
    }
}