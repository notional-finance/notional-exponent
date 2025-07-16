import { VaultRewardUpdate } from "../generated/templates/Vault/IYieldStrategy";
import { UNDERLYING } from "./constants";
import { createERC20TokenAsset } from "./entities/token";

export function handleVaultRewardUpdate(event: VaultRewardUpdate): void {
  createERC20TokenAsset(event.params.rewardToken, event, UNDERLYING);
}
