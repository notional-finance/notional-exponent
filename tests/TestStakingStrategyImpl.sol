// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "./TestWithdrawRequestImpl.sol";
import "../src/staking/AbstractStakingStrategy.sol";
import "../src/staking/StakingStrategy.sol";
import "../src/withdraws/EtherFi.sol";
import "../src/withdraws/Dinero.sol";
import "../src/withdraws/Midas.sol";
import "../src/staking/MidasStakingStrategy.sol";
import "../src/interfaces/ITradingModule.sol";
import "../src/oracles/MidasOracle.sol";
import "./TestStakingStrategy.sol";
import "./Mocks.sol";

contract TestMockStakingStrategy_EtherFi is TestStakingStrategy {
    function getRedeemData(
        address, /* user */
        uint256 /* shares */
    )
        internal
        pure
        override
        returns (bytes memory redeemData)
    {
        return abi.encode(
            RedeemParams({
                minPurchaseAmount: 0,
                dexId: uint8(DexId.CURVE_V2),
                exchangeData: abi.encode(
                    CurveV2SingleData({ pool: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5, fromIndex: 1, toIndex: 0 })
                )
            })
        );
    }

    function deployYieldStrategy() internal override {
        setupWithdrawRequestManager(address(new EtherFiWithdrawRequestManager()));
        y = new MockStakingStrategy(address(WETH), address(weETH), 0.001e18);

        w = ERC20(y.yieldToken());
        (AggregatorV2V3Interface oracle,) = TRADING_MODULE.priceOracles(address(w));
        o = new MockOracle(oracle.latestAnswer());

        defaultDeposit = 10e18;
        defaultBorrow = 90e18;
        maxEntryValuationSlippage = 0.005e18;
        maxExitValuationSlippage = 0.005e18;

        withdrawRequest = new TestEtherFiWithdrawRequest();
        canInspectTransientVariables = true;
        canMintYieldTokens = true;
    }

    function postDeploySetup() internal override {
        vm.startPrank(owner);
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(weETH),
            ITradingModule.TokenPermissions({
                allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5
            })
        );
        vm.stopPrank();
    }
}

contract TestStakingStrategy_EtherFi is TestStakingStrategy {
    function getRedeemData(
        address, /* user */
        uint256 /* shares */
    )
        internal
        pure
        override
        returns (bytes memory redeemData)
    {
        return abi.encode(
            RedeemParams({
                minPurchaseAmount: 0,
                dexId: uint8(DexId.CURVE_V2),
                exchangeData: abi.encode(
                    CurveV2SingleData({ pool: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5, fromIndex: 1, toIndex: 0 })
                )
            })
        );
    }

    function deployYieldStrategy() internal override {
        setupWithdrawRequestManager(address(new EtherFiWithdrawRequestManager()));
        y = new StakingStrategy(address(WETH), address(weETH), 0.001e18);

        w = ERC20(y.yieldToken());
        (AggregatorV2V3Interface oracle,) = TRADING_MODULE.priceOracles(address(w));
        o = new MockOracle(oracle.latestAnswer());

        defaultDeposit = 10e18;
        defaultBorrow = 90e18;
        maxEntryValuationSlippage = 0.005e18;
        maxExitValuationSlippage = 0.005e18;

        withdrawRequest = new TestEtherFiWithdrawRequest();
    }

    function postDeploySetup() internal override {
        vm.startPrank(owner);
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(weETH),
            ITradingModule.TokenPermissions({
                allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5
            })
        );
        vm.stopPrank();
    }

    function test_accountingAsset() public view {
        assertEq(y.accountingAsset(), address(WETH));
    }
}

contract TestStakingStrategy_Ethena is TestStakingStrategy {
    function getRedeemData(
        address, /* user */
        uint256 /* shares */
    )
        internal
        override
        returns (bytes memory redeemData)
    {
        // There is no instant redeem for Ethena
        vm.skip(true);
        return bytes("");
    }

    function getDepositData(
        address, /* user */
        uint256 /* assets */
    )
        internal
        pure
        override
        returns (bytes memory depositData)
    {
        return abi.encode(
            StakingTradeParams({
                tradeType: TradeType.EXACT_IN_SINGLE,
                minPurchaseAmount: 0,
                dexId: uint8(DexId.CURVE_V2),
                exchangeData: abi.encode(
                    CurveV2SingleData({ pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72, fromIndex: 1, toIndex: 0 })
                ),
                stakeData: bytes("")
            })
        );
    }

    function deployYieldStrategy() internal override {
        setupWithdrawRequestManager(address(new EthenaWithdrawRequestManager()));
        y = new StakingStrategy(address(USDC), address(sUSDe), 0.001e18);

        w = ERC20(y.yieldToken());
        (AggregatorV2V3Interface oracle,) = TRADING_MODULE.priceOracles(address(w));
        o = new MockOracle(oracle.latestAnswer() * 1e18 / 1e8);

        // Ethena uses USDe as the withdraw token during valuation
        (oracle,) = TRADING_MODULE.priceOracles(address(USDe));
        withdrawTokenOracle = new MockOracle(oracle.latestAnswer() * 1e18 / 1e8);
        vm.prank(owner);
        TRADING_MODULE.setPriceOracle(address(USDe), AggregatorV2V3Interface(address(withdrawTokenOracle)));

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
        maxEntryValuationSlippage = 0.005e18;
        maxExitValuationSlippage = 0.005e18;

        withdrawRequest = new TestEthenaWithdrawRequest();
    }

    function postDeploySetup() internal override {
        vm.startPrank(owner);
        TRADING_MODULE.setTokenPermissions(
            address(manager),
            address(USDC),
            ITradingModule.TokenPermissions({
                allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5
            })
        );
        vm.stopPrank();
    }

    function test_accountingAsset() public view {
        assertEq(y.accountingAsset(), address(USDe));
    }
}

abstract contract TestStakingStrategy_Midas is TestStakingStrategy {
    function overrideForkBlock() internal override {
        FORK_BLOCK = 24_034_331;
    }

    function getDepositData(
        address, /* user */
        uint256 /* assets */
    )
        internal
        pure
        virtual
        override
        returns (bytes memory depositData)
    {
        return abi.encode(0);
    }

    function getRedeemData(
        address, /* user */
        uint256 /* shares */
    )
        internal
        pure
        virtual
        override
        returns (bytes memory redeemData)
    {
        return abi.encode(0);
    }

    function vaults()
        internal
        view
        virtual
        returns (IDepositVault depositVault, IRedemptionVault redemptionVault, address asset);

    function withdrawManagers() internal virtual returns (TestWithdrawRequest tw, IWithdrawRequestManager wrm);

    function deployYieldStrategy() internal override {
        (IDepositVault depositVault, IRedemptionVault redemptionVault, address asset) = vaults();
        (TestWithdrawRequest tw, IWithdrawRequestManager wrm) = withdrawManagers();
        withdrawRequest = tw;
        address mToken = depositVault.mToken();
        setupWithdrawRequestManager(address(wrm));
        TestMidas_mHYPER_USDC_WithdrawRequest(address(withdrawRequest)).setManager(address(manager));
        y = new MidasStakingStrategy(address(asset), address(mToken), 0.001e18);

        w = ERC20(y.yieldToken());
        MidasOracle oracle = new MidasOracle("Midas USD Oracle", depositVault, address(asset));
        int256 latestPrice = oracle.latestAnswer();
        o = new MockOracle(latestPrice);

        defaultDeposit = 1000e6;
        defaultBorrow = 9000e6;
        maxEntryValuationSlippage = 0.005e18;
        // This is the worst case slippage for an instant exit from the mHYPER vault, it is
        // 50 bps * the default leverage (11x)
        maxExitValuationSlippage = 0.055e18;
        // This is the variationTolerance of the mHYPER vault
        maxWithdrawValuationChange = 0.007e18;
        // Cannot warp forward due to feed health check.
        skipFeeCollectionTest = true;
        // The known token prevents liquidation unless the interest accrues past the collateral value.
        knownTokenPreventsLiquidation = true;
    }

    function postDeploySetup() internal virtual override {
        (IDepositVault depositVault,,) = vaults();
        if (depositVault.greenlistEnabled()) {
            address GREENLISTED_ROLE_OPERATOR = 0x4f75307888fD06B16594cC93ED478625AD65EEea;
            vm.startPrank(GREENLISTED_ROLE_OPERATOR);
            IMidasAccessControl accessControl = IMidasAccessControl(depositVault.accessControl());
            bytes32 greenlistedRole = accessControl.GREENLISTED_ROLE();
            accessControl.grantRole(greenlistedRole, address(manager));
            accessControl.grantRole(greenlistedRole, msg.sender);
            vm.stopPrank();
        }
    }

    function test_midas_hardcoded_price() public view {
        (int256 price,) = TRADING_MODULE.getOraclePrice(address(w), address(asset));
        (IDepositVault depositVault,,) = vaults();
        uint256 midasPrice = IMidasDataFeed(depositVault.mTokenDataFeed()).getDataInBase18();
        assertApproxEqAbs(uint256(price), midasPrice, 1);
    }

    function test_accountingAsset() public view {
        assertEq(y.accountingAsset(), address(asset));
    }
}

contract TestStakingStrategy_Midas_mHYPER_USDC is TestStakingStrategy_Midas {
    function vaults()
        internal
        view
        override
        returns (IDepositVault depositVault, IRedemptionVault redemptionVault, address asset)
    {
        return (
            IDepositVault(0xbA9FD2850965053Ffab368Df8AA7eD2486f11024),
            IRedemptionVault(0x6Be2f55816efd0d91f52720f096006d63c366e98),
            address(USDC)
        );
    }

    function withdrawManagers() internal override returns (TestWithdrawRequest tw, IWithdrawRequestManager wrm) {
        (IDepositVault depositVault, IRedemptionVault redemptionVault,) = vaults();
        return (
            new TestMidas_mHYPER_USDC_WithdrawRequest(),
            IWithdrawRequestManager(
                new MidasWithdrawRequestManager(address(USDC), address(USDC), depositVault, redemptionVault)
            )
        );
    }
}

contract TestStakingStrategy_Midas_mAPOLLO_USDC is TestStakingStrategy_Midas {
    function vaults()
        internal
        view
        override
        returns (IDepositVault depositVault, IRedemptionVault redemptionVault, address asset)
    {
        return (
            IDepositVault(0xc21511EDd1E6eCdc36e8aD4c82117033e50D5921),
            IRedemptionVault(0x5aeA6D35ED7B3B7aE78694B7da2Ee880756Af5C0),
            address(USDC)
        );
    }

    function withdrawManagers() internal override returns (TestWithdrawRequest tw, IWithdrawRequestManager wrm) {
        (IDepositVault depositVault, IRedemptionVault redemptionVault,) = vaults();
        return (
            new TestMidas_mAPOLLO_USDC_WithdrawRequest(),
            IWithdrawRequestManager(
                new MidasWithdrawRequestManager(address(USDC), address(USDC), depositVault, redemptionVault)
            )
        );
    }
}

contract TestStakingStrategy_Midas_mHyperBTC_WBTC is TestStakingStrategy_Midas {
    // NOTE: there is a minAmountForFirstDeposit for this vault.
    function vaults()
        internal
        view
        override
        returns (IDepositVault depositVault, IRedemptionVault redemptionVault, address asset)
    {
        return (
            IDepositVault(0xeD22A9861C6eDd4f1292aeAb1E44661D5f3FE65e),
            IRedemptionVault(0x16d4f955B0aA1b1570Fe3e9bB2f8c19C407cdb67),
            address(WBTC)
        );
    }

    function withdrawManagers() internal override returns (TestWithdrawRequest tw, IWithdrawRequestManager wrm) {
        (IDepositVault depositVault, IRedemptionVault redemptionVault,) = vaults();
        return (
            new TestMidas_mHyperBTC_WBTC_WithdrawRequest(),
            IWithdrawRequestManager(
                new MidasWithdrawRequestManager(address(cbBTC), address(WBTC), depositVault, redemptionVault)
            )
        );
    }

    function postDeploySetup() internal override {
        super.postDeploySetup();
        vm.startPrank(owner);
        TRADING_MODULE.setPriceOracle(
            address(cbBTC), AggregatorV2V3Interface(0x2665701293fCbEB223D11A08D826563EDcCE423A)
        );
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(cbBTC),
            ITradingModule.TokenPermissions({
                allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5
            })
        );
        vm.stopPrank();

        // Instant withdraws won't work unless we deal some cbBTC to the redemption vault.
        (, IRedemptionVault redemptionVault,) = vaults();
        deal(address(cbBTC), address(redemptionVault), 100e8);

        defaultDeposit = 0.1e8;
        defaultBorrow = 0.9e8;
        // This has to increase here because the withdraw token is not the same as the asset so
        // this will need to account for valuation deviations.
        maxWithdrawValuationChange = 0.0175e18;
    }

    function getRedeemData(
        address, /* user */
        uint256 /* shares */
    )
        internal
        pure
        override
        returns (bytes memory redeemData)
    {
        return abi.encode(
            RedeemParams({
                minPurchaseAmount: 0,
                dexId: uint8(DexId.CURVE_V2),
                exchangeData: abi.encode(
                    CurveV2SingleData({ pool: 0x839d6bDeDFF886404A6d7a788ef241e4e28F4802, fromIndex: 0, toIndex: 1 })
                )
            })
        );
    }
}
