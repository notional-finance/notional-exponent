// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "forge-std/src/console.sol";

import "../interfaces/Errors.sol";

import {IRewardManager} from "../interfaces/IRewardManager.sol";
import {ILendingRouter} from "../interfaces/ILendingRouter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TokenUtils} from "../utils/TokenUtils.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYieldStrategy} from "../interfaces/IYieldStrategy.sol";
import {MORPHO, MarketParams, Id, Position, Market} from "../interfaces/Morpho/IMorpho.sol";
import {IMorphoLiquidateCallback, IMorphoFlashLoanCallback, IMorphoRepayCallback} from "../interfaces/Morpho/IMorphoCallbacks.sol";
import {ADDRESS_REGISTRY} from "../utils/Constants.sol";

struct MorphoParams {
    address irm;
    uint256 lltv;
}

struct MigrateParams {
    address fromLendingRouter;
    uint256 sharesToMigrate;
    uint256 assetToRepay;
}

contract MorphoLendingRouter is ILendingRouter, IMorphoLiquidateCallback, IMorphoFlashLoanCallback, IMorphoRepayCallback {
    using SafeERC20 for ERC20;
    using TokenUtils for ERC20;

    mapping(address user => mapping(address operator => bool approved)) private s_isApproved;
    mapping(address vault => mapping(address user => uint256 lastEntryTime)) private s_lastEntryTime;
    mapping(address vault => MorphoParams params) private s_morphoParams;

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

    function initializeMarket(address vault, address irm, uint256 lltv) external {
        require(ADDRESS_REGISTRY.upgradeAdmin() == msg.sender);
        // Cannot override parameters once they are set
        require(s_morphoParams[vault].irm == address(0));
        require(s_morphoParams[vault].lltv == 0);

        s_morphoParams[vault] = MorphoParams({
            irm: irm,
            lltv: lltv
        });

        MORPHO.createMarket(marketParams(vault));
    }

    function marketParams(address vault) public view returns (MarketParams memory) {
        address asset = IYieldStrategy(vault).asset();
        MorphoParams memory params = s_morphoParams[vault];

        return MarketParams({
            loanToken: asset,
            collateralToken: vault,
            oracle: vault,
            irm: params.irm,
            lltv: params.lltv
        });
    }

    function morphoId(address vault) public view returns (Id) {
        return Id.wrap(keccak256(abi.encode(marketParams(vault))));
    }

    function enterPosition(
        address onBehalf,
        address vault,
        uint256 depositAssetAmount,
        uint256 borrowAmount,
        bytes calldata depositData
    ) external override {
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
        MarketParams memory m = marketParams(vault);

        // First collect the margin deposit
        if (depositAssetAmount > 0) {
            ERC20(m.loanToken).safeTransferFrom(msg.sender, address(this), depositAssetAmount);
        }

        // TODO: if migrate data is set and we have a max repay how do we get the borrow amount?

        if (borrowAmount > 0) {
            // At this point we will flash borrow funds from the lending market and then
            // receive control in a different function on a callback.
            bytes memory flashLoanData = abi.encode(
                m, depositAssetAmount, depositData, onBehalf, migrateData
            );
            MORPHO.flashLoan(m.loanToken, borrowAmount, flashLoanData);
        } else {
            _supplyCollateral(m, depositAssetAmount, depositData, onBehalf, migrateData);
        }

        s_lastEntryTime[vault][onBehalf] = block.timestamp;
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external override {
        require(msg.sender == address(MORPHO));

        (
            MarketParams memory m,
            uint256 depositAssetAmount,
            bytes memory depositData,
            address receiver,
            bytes memory migrateData
        ) = abi.decode(data, (MarketParams, uint256, bytes, address, bytes));

        _supplyCollateral(m, depositAssetAmount + assets, depositData, receiver, migrateData);

        // Borrow the assets in order to repay the flash loan
        MORPHO.borrow(m, assets, 0, receiver, address(this));

        // Allow for flash loan to be repaid
        ERC20(m.loanToken).checkApprove(address(MORPHO), assets);
    }

    function _supplyCollateral(
        MarketParams memory m,
        uint256 assetAmount,
        bytes memory depositData,
        address receiver,
        bytes memory migrateData
    ) internal {
        uint256 sharesReceived;
        if (0 < migrateData.length) {
            (
                address fromLendingRouter,
                uint256 sharesToMigrate,
                uint256 assetToRepay
            ) = abi.decode(migrateData, (address, uint256, uint256));
            require(ADDRESS_REGISTRY.isLendingRouter(fromLendingRouter), "Invalid lending router");

            // Allow the previous lending router to repay the debt from assets held here.
            ERC20(m.loanToken).approve(fromLendingRouter, assetToRepay);
            // On migrate the receiver is this current lending router
            ILendingRouter(fromLendingRouter).exitPosition(
                receiver, m.collateralToken, address(this), sharesToMigrate, assetToRepay, bytes("")
            );
            sharesReceived = sharesToMigrate;
            // TODO: is this vulnerable to donation attack?
            assetAmount = ERC20(m.loanToken).balanceOf(address(this));
        }

        if (0 < assetAmount) {
            ERC20(m.loanToken).approve(m.collateralToken, assetAmount);
            sharesReceived += IYieldStrategy(m.collateralToken).mintShares(
                assetAmount, receiver, depositData
            );
        }

        // Allows the transfer from the lending market to the sharesOwner
        IYieldStrategy(m.collateralToken).allowTransfer(address(MORPHO), sharesReceived);

        // We should receive shares in return
        ERC20(m.collateralToken).approve(address(MORPHO), sharesReceived);
        MORPHO.supplyCollateral(m, sharesReceived, receiver, "");
    }

    function exitPosition(
        address onBehalf,
        address vault,
        address receiver,
        uint256 sharesToRedeem,
        uint256 assetToRepay,
        bytes calldata redeemData
    ) external override isAuthorized(onBehalf) {
        if (block.timestamp - s_lastEntryTime[vault][onBehalf] < 5 minutes) {
            revert CannotExitPositionWithinCooldownPeriod();
        }

        MarketParams memory m = marketParams(vault);
        if (0 < assetToRepay) {
            uint256 sharesToRepay;
            if (assetToRepay == type(uint256).max) {
                // If assetToRepay is uint256.max then get the morpho borrow shares amount to
                // get a full exit.
                sharesToRepay = MORPHO.position(morphoId(vault), onBehalf).borrowShares;
                assetToRepay = 0;
            }

            bytes memory repayData = abi.encode(
                onBehalf, m, receiver, sharesToRedeem, redeemData, _isMigrate(receiver)
            );

            // Will trigger a callback to onMorphoRepay
            MORPHO.repay(m, assetToRepay, sharesToRepay, onBehalf, repayData);
        } else {
            address migrateTo = _isMigrate(receiver) ? receiver : address(0);
            uint256 assetsWithdrawn = _redeemShares(m, onBehalf, migrateTo, sharesToRedeem, redeemData);
            if (0 < assetsWithdrawn) ERC20(m.loanToken).safeTransfer(receiver, assetsWithdrawn);
        }
    }

    function _isMigrate(address receiver) internal view returns (bool) {
        return receiver == msg.sender && ADDRESS_REGISTRY.isLendingRouter(msg.sender);
    }

    function _redeemShares(
        MarketParams memory m,
        address sharesOwner,
        address migrateTo,
        uint256 sharesToRedeem,
        bytes memory redeemData
    ) internal returns (uint256 assetsWithdrawn) {
        address receiver;
        uint256 balanceBefore;
        if (migrateTo == address(0)) {
            receiver = sharesOwner;
            balanceBefore = balanceOfCollateral(sharesOwner, m.collateralToken);
        } else {
            // If we are migrating shares then we need to transfer them to the new lending router and
            // we do not need to track the balance before.
            receiver = migrateTo;
        }

        // Allows the transfer from the lending market to the sharesOwner
        IYieldStrategy(m.collateralToken).allowTransfer(receiver, sharesToRedeem);

        MORPHO.withdrawCollateral(m, sharesToRedeem, sharesOwner, receiver);

        // If we are not migrating then burn the shares
        if (migrateTo == address(0)) {
            assetsWithdrawn = IYieldStrategy(m.collateralToken).burnShares(
                sharesOwner, sharesToRedeem, balanceBefore, redeemData
            );
        }
    }

    function onMorphoRepay(uint256 assetToRepay, bytes calldata data) external override {
        require(msg.sender == address(MORPHO));

        (
            address sharesOwner,
            MarketParams memory m,
            address receiver,
            uint256 sharesToRedeem,
            bytes memory redeemData,
            bool isMigrate
        ) = abi.decode(data, (address, MarketParams, address, uint256, bytes, bool));

        uint256 assetsWithdrawn = _redeemShares(
            m, sharesOwner, isMigrate ? receiver : address(0), sharesToRedeem, redeemData
        );

        if (isMigrate) {
            // When migrating we do not withdraw any assets and we must repay the entire debt
            // from the previous lending router.
            ERC20(m.loanToken).safeTransferFrom(receiver, address(this), assetToRepay);
            assetsWithdrawn = assetToRepay;
        }

        // Transfer any profits to the receiver
        if (assetsWithdrawn < assetToRepay) {
            // We have to revert in this case because we've already redeemed the yield tokens
            revert InsufficientAssetsForRepayment(assetToRepay, assetsWithdrawn);
        }

        uint256 profitsWithdrawn;
        unchecked {
            profitsWithdrawn = assetsWithdrawn - assetToRepay;
        }
        ERC20(m.loanToken).safeTransfer(receiver, profitsWithdrawn);

        // Allow morpho to repay the debt
        ERC20(m.loanToken).checkApprove(address(MORPHO), assetToRepay);
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

        MarketParams memory m = marketParams(vault);
        IYieldStrategy(vault).preLiquidation(
            liquidator, liquidateAccount, seizedAssets, balanceOfCollateral(liquidateAccount, vault)
        );

        (sharesToLiquidator, /* */) = MORPHO.liquidate(
            m, liquidateAccount, seizedAssets, repaidShares,
            abi.encode(m.loanToken, liquidator)
        );

        IYieldStrategy(vault).postLiquidation(liquidator, liquidateAccount, sharesToLiquidator);

        // The liquidator will receive shares in their native balance and then they can call redeem
        // on the yield strategy to get the assets.
    }

    function onMorphoLiquidate(uint256 repaidAssets, bytes calldata data) external override {
        require(msg.sender == address(MORPHO));
        (address asset, address liquidator) = abi.decode(data, (address, address));

        ERC20(asset).safeTransferFrom(liquidator, address(this), repaidAssets);
        ERC20(asset).checkApprove(address(MORPHO), repaidAssets);
    }

    function balanceOfCollateral(address account, address vault) public view returns (uint256 collateralBalance) {
        collateralBalance = MORPHO.position(morphoId(vault), account).collateral;
    }

    function healthFactor(address borrower, address vault) public returns (uint256 borrowed, uint256 collateralValue, uint256 maxBorrow) {
        MarketParams memory m = marketParams(vault);
        Id id = morphoId(vault);
        Position memory position = MORPHO.position(id, borrower);
        Market memory market = MORPHO.market(id);

        if (position.borrowShares > 0) {
            borrowed = (uint256(position.borrowShares) * uint256(market.totalBorrowAssets)) / uint256(market.totalBorrowShares);
        } else {
            borrowed = 0;
        }
        collateralValue = (uint256(position.collateral) * IYieldStrategy(vault).price(borrower)) / 1e36;
        maxBorrow = collateralValue * m.lltv / 1e18;
    }

    function initiateWithdraw(address vault, bytes calldata data) external returns (uint256 requestId) {
        requestId = _initiateWithdraw(vault, msg.sender, data);

        // Can only initiate a withdraw if health factor remains positive
        (uint256 borrowed, /* */, uint256 maxBorrow) = healthFactor(msg.sender, vault);
        if (borrowed > maxBorrow) revert CannotInitiateWithdraw(msg.sender);

        // TODO: emit event
    }

    function forceWithdraw(address vault, address account, bytes calldata data) external returns (uint256 requestId) {
        // Can only force a withdraw if health factor is negative, this allows a liquidator to
        // force a withdraw and liquidate a position at a later time.
        (uint256 borrowed, /* */, uint256 maxBorrow) = healthFactor(account, vault);
        if (borrowed <= maxBorrow) revert CannotForceWithdraw(account);

        requestId = _initiateWithdraw(vault, account, data);

        // TODO: emit event
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
