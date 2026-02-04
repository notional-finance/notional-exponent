// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

interface IdleCDOEpochVariant {
    function AATranche() external view returns (address);
    function token() external view returns (address);
    // Returns the amount of tokens received
    function depositAA(uint256 _amount) external returns (uint256);
    function depositDuringEpoch(uint256 _amount, address _tranche) external returns (uint256);
    function isWalletAllowed(address user) external view returns (bool);
    function isEpochRunning() external view returns (bool);
    function isDepositDuringEpochDisabled() external view returns (bool);
    function epochEndDate() external view returns (uint256);
    function isAYSActive() external view returns (bool);

    function claimInstantWithdrawRequest() external;
    function claimWithdrawRequest() external;
}

contract ParetoWithdrawHolder is ClonedCoolDownHolder {
    constructor(address _manager) ClonedCoolDownHolder(_manager) { }

    // @notice There is no way to stop a cool down
    function _stopCooldown() internal pure override {
        revert();
    }

    function _startCooldown(uint256 cooldownBalance) internal override {
        // TODO: there is an issue where this will revert if the cool down holder is not whitelisted
        // by the pareto vault

        // This requests all the tokens to be burned
        paretoVault.requestWithdraw(0, paretoVault.AATranche());
    }

    function _finalizeCooldown() internal override returns (uint256 tokensWithdrawn, bool finalized) {
        if (paretoVault.isInstantWithdrawRequestClaimable()) {
            paretoVault.claimInstantWithdrawRequest();
        }
        paretoVault.claimWithdrawRequest();
    }
}

contract ParetoWithdrawRequestManager is AbstractWithdrawRequestManager {
    IdleCDOEpochVariant public immutable paretoVault;
    address public HOLDER_IMPLEMENTATION;

    constructor(IdleCDOEpochVariant _paretoVault)
        AbstractWithdrawRequestManager(_paretoVault.token(), _paretoVault.AATranche(), _paretoVault.token())
    {
        paretoVault = _paretoVault;
    }

    function redeployHolder() external {
        require(msg.sender == ADDRESS_REGISTRY.upgradeAdmin());
        HOLDER_IMPLEMENTATION = address(new ParetoWithdrawHolder(address(this)));
    }

    function _stakeTokens(
        uint256 amount,
        bytes memory /* stakeData */
    )
        internal
        override
    {
        bool isEpochRunning = paretoVault.isEpochRunning();
        if (isEpochRunning) {
            require(paretoVault.isDepositDuringEpochDisabled() == false, "Deposit during epoch is disabled");
            require(block.timestamp < paretoVault.epochEndDate(), "Epoch has ended");
            require(paretoVault.isAYSActive() == false, "AYS is active");
            ERC20(STAKING_TOKEN).approve(address(paretoVault), amount);
            // Deposit into the AATranche
            paretoVault.depositDuringEpoch(amount, YIELD_TOKEN);
        } else {
            ERC20(STAKING_TOKEN).approve(address(paretoVault), amount);
            paretoVault.depositAA(amount);
        }
    }

    function _initiateWithdrawImpl(
        address account,
        uint256 amountToWithdraw,
        bytes calldata, /* data */
        address /* forceWithdrawFrom */
    )
        internal
        override
        returns (uint256 requestId)
    {
        if (!paretoVault.isWalletAllowed(account)) revert ParetoBlockedAccount(account);

        ParetoWithdrawHolder holder = ParetoWithdrawHolder(Clones.clone(HOLDER_IMPLEMENTATION));
        ERC20(YIELD_TOKEN).transfer(address(holder), amountToWithdraw);
        holder.startCooldown(amountToWithdraw);

        return uint256(uint160(address(holder)));
    }
}
