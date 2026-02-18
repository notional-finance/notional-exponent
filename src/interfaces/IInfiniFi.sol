// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

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
    error TransferFailed();
    error UserNotUnwinding();
    error UserUnwindingNotStarted();
    error UserUnwindingInprogress();

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

IGateway constant INFINIFI_GATEWAY = IGateway(0x3f04b65Ddbd87f9CE0A2e7Eb24d80e7fb87625b5);
address constant iUSD = 0x48f9e38f3070AD8945DFEae3FA70987722E3D89c;
