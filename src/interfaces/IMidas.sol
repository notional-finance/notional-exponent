// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

enum MidasRequestStatus {
    Pending,
    Processed,
    Canceled
}

interface IMidasAccessControl {
    function GREENLISTED_ROLE() external view returns (bytes32);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 role, address account) external;
}

interface IMidasDataFeed {
    function getDataInBase18() external view returns (uint256);
    function aggregator() external view returns (address);
}

interface IMidasVault {
    struct TokenConfig {
        address dataFeed;
        uint256 fee;
        uint256 allowance;
        bool stable;
    }

    function mToken() external view returns (address);
    function getPaymentTokens() external view returns (address[] memory);
    function tokensConfig(address token) external view returns (TokenConfig memory);
    function greenlistEnabled() external view returns (bool);
    function accessControl() external view returns (IMidasAccessControl);
    function instantFee() external view returns (uint256);
    function variationTolerance() external view returns (uint256);
    function mTokenDataFeed() external view returns (address);
}

interface IDepositVault is IMidasVault {
    function depositInstant(
        address tokenIn,
        uint256 amountToken,
        uint256 minReceiveAmount,
        bytes32 referrerId
    )
        external;
}

interface IRedemptionVault is IMidasVault {
    struct Request {
        address sender;
        address tokenOut;
        MidasRequestStatus status;
        uint256 amountMToken;
        uint256 mTokenRate;
        uint256 tokenOutRate;
    }

    function redeemRequests(uint256 requestId) external view returns (Request memory);
    function redeemRequest(address tokenOut, uint256 amountMTokenIn) external returns (uint256 requestId);
    function redeemInstant(address tokenOut, uint256 amountMTokenIn, uint256 minReceiveAmount) external;
}

IMidasAccessControl constant MidasAccessControl = IMidasAccessControl(0x0312A9D1Ff2372DDEdCBB21e4B6389aFc919aC4B);
bytes32 constant MIDAS_GREENLISTED_ROLE = 0xd2576bd6a4c5558421de15cb8ecdf4eb3282aac06b94d4f004e8cd0d00f3ebd8;

/**
 * @title DecimalsCorrectionLibrary
 * @author RedDuck Software
 */
library DecimalsCorrectionLibrary {
    /**
     * @dev converts `originalAmount` with `originalDecimals` into
     * amount with `decidedDecimals`
     * @param originalAmount amount to convert
     * @param originalDecimals decimals of the original amount
     * @param decidedDecimals decimals for the output amount
     * @return amount converted amount with `decidedDecimals`
     */
    function convert(
        uint256 originalAmount,
        uint256 originalDecimals,
        uint256 decidedDecimals
    )
        internal
        pure
        returns (uint256)
    {
        if (originalAmount == 0) return 0;
        if (originalDecimals == decidedDecimals) return originalAmount;

        uint256 adjustedAmount;

        if (originalDecimals > decidedDecimals) {
            adjustedAmount = originalAmount / (10 ** (originalDecimals - decidedDecimals));
        } else {
            adjustedAmount = originalAmount * (10 ** (decidedDecimals - originalDecimals));
        }

        return adjustedAmount;
    }

    /**
     * @dev converts `originalAmount` with decimals 18 into
     * amount with `decidedDecimals`
     * @param originalAmount amount to convert
     * @param decidedDecimals decimals for the output amount
     * @return amount converted amount with `decidedDecimals`
     */
    function convertFromBase18(uint256 originalAmount, uint256 decidedDecimals) internal pure returns (uint256) {
        return convert(originalAmount, 18, decidedDecimals);
    }

    /**
     * @dev converts `originalAmount` with `originalDecimals` into
     * amount with decimals 18
     * @param originalAmount amount to convert
     * @param originalDecimals decimals of the original amount
     * @return amount converted amount with 18 decimals
     */
    function convertToBase18(uint256 originalAmount, uint256 originalDecimals) internal pure returns (uint256) {
        return convert(originalAmount, originalDecimals, 18);
    }
}
