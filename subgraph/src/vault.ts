import { VaultRewardTransfer, VaultRewardUpdate } from "../generated/templates/Vault/IYieldStrategy";
import { UNDERLYING } from "./constants";
import { loadAccount } from "./entities/account";
import { createSnapshotForIncentives } from "./entities/balance";
import { createERC20TokenAsset } from "./entities/token";

export function handleVaultRewardUpdate(event: VaultRewardUpdate): void {
  createERC20TokenAsset(event.params.rewardToken, event, UNDERLYING);
}

export function handleVaultRewardTransfer(event: VaultRewardTransfer): void {
  let account = loadAccount(event.params.account.toHexString(), event);
  createSnapshotForIncentives(account, event.address, event.params.token, event.params.amount, event);
}
