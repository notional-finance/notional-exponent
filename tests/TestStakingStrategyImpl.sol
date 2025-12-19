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

contract TestStakingStrategy_Midas_mHYPER_USDC is TestStakingStrategy {
    function overrideForkBlock() internal override {
        FORK_BLOCK = 24_034_331;
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
        return abi.encode(0);
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
        return abi.encode(0);
    }

    function deployYieldStrategy() internal override {
        withdrawRequest = new TestMidas_mHYPER_USDC_WithdrawRequest();
        address mHYPER = 0x9b5528528656DBC094765E2abB79F293c21191B9;
        IDepositVault depositVault = IDepositVault(0xbA9FD2850965053Ffab368Df8AA7eD2486f11024);
        IRedemptionVault redemptionVault = IRedemptionVault(0x6Be2f55816efd0d91f52720f096006d63c366e98);
        address wrm =
            address(new MidasWithdrawRequestManager(address(USDC), depositVault, redemptionVault, bytes32(uint256(0))));

        setupWithdrawRequestManager(address(wrm));
        TestMidas_mHYPER_USDC_WithdrawRequest(address(withdrawRequest)).setManager(address(manager));
        y = new MidasStakingStrategy(address(USDC), address(mHYPER), 0.001e18);

        w = ERC20(y.yieldToken());
        uint256 latestPrice = IMidasDataFeed(depositVault.mTokenDataFeed()).getDataInBase18();
        o = new MockOracle(int256(latestPrice));

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
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

    function test_accountingAsset() public view {
        assertEq(y.accountingAsset(), address(USDC));
    }
}
