// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { StakingStrategy } from "./StakingStrategy.sol";
import { ParetoWithdrawRequestManager } from "../withdraws/Pareto.sol";
import { IdleCDOEpochVariant } from "../interfaces/IPareto.sol";

contract ParetoStakingStrategy is StakingStrategy {
    error ParetoBlockedAccount(address account);

    constructor(address _asset, address _yieldToken, uint256 _feeRate)
        StakingStrategy(_asset, _yieldToken, _feeRate)
    { }

    function strategy() public pure override returns (string memory) {
        return "ParetoStaking";
    }

    function _checkParetoAccount(address account) internal view {
        ParetoWithdrawRequestManager wrm = ParetoWithdrawRequestManager(address(withdrawRequestManager));
        IdleCDOEpochVariant paretoVault = IdleCDOEpochVariant(wrm.paretoVault());
        if (!paretoVault.isWalletAllowed(account)) revert ParetoBlockedAccount(account);
    }

    function _mintYieldTokens(uint256 assets, address receiver, bytes memory depositData) internal override {
        _checkParetoAccount(receiver);
        super._mintYieldTokens(assets, receiver, depositData);
    }
}
