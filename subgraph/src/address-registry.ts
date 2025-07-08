import {
  AccountPositionCleared,
  AccountPositionCreated,
  LendingRouterSet,
  WhitelistedVault,
  WithdrawRequestManagerSet
} from "../generated/AddressRegistry/AddressRegistry"
import { IYieldStrategy } from "../generated/AddressRegistry/IYieldStrategy"
import { IWithdrawRequestManager } from "../generated/AddressRegistry/IWithdrawRequestManager"
import { LendingRouter, Vault, WithdrawRequestManager } from "../generated/schema"
import { createERC20TokenAsset } from "./entities/token"
import { createAccount } from "./entities/account"
import { UNDERLYING, VAULT_SHARE } from "./constants"
import { 
  Vault as VaultTemplate,
  WithdrawRequestManager as WithdrawRequestManagerTemplate,
  LendingRouter as LendingRouterTemplate
} from "../generated/templates"

export function handleAccountPositionCleared(
  event: AccountPositionCleared
): void { 
  // TODO: delete balances
}

export function handleAccountPositionCreated(
  event: AccountPositionCreated
): void {
  const id = event.params.account.toHexString();
  createAccount(id, event);
}

export function handleLendingRouterSet(event: LendingRouterSet): void {
  const id = event.params.lendingRouter.toHexString();
  let lendingRouter = LendingRouter.load(id);
  if (!lendingRouter) {
    lendingRouter = new LendingRouter(id);
    lendingRouter.firstUpdateBlockNumber = event.block.number;
    lendingRouter.firstUpdateTimestamp = event.block.timestamp.toI32();
    lendingRouter.firstUpdateTransactionHash = event.transaction.hash;
  }

  lendingRouter.lastUpdateBlockNumber = event.block.number;
  lendingRouter.lastUpdateTimestamp = event.block.timestamp.toI32();
  lendingRouter.lastUpdateTransactionHash = event.transaction.hash;
  lendingRouter.save();

  LendingRouterTemplate.create(event.params.lendingRouter);
}

export function handleWhitelistedVault(event: WhitelistedVault): void {
  const id = event.params.vault.toHexString();
  let vault = Vault.load(id);
  if (!vault) {
    vault = new Vault(id);
    vault.firstUpdateBlockNumber = event.block.number;
    vault.firstUpdateTimestamp = event.block.timestamp.toI32();
    vault.firstUpdateTransactionHash = event.transaction.hash;
  }

  vault.isWhitelisted = event.params.isWhitelisted;
  vault.lastUpdateBlockNumber = event.block.number;
  vault.lastUpdateTimestamp = event.block.timestamp.toI32();
  vault.lastUpdateTransactionHash = event.transaction.hash;

  let yieldStrategy = IYieldStrategy.bind(event.params.vault);
  vault.feeRate = yieldStrategy.feeRate();
  vault.yieldToken = createERC20TokenAsset(yieldStrategy.yieldToken(), event, UNDERLYING).id;
  vault.asset = createERC20TokenAsset(yieldStrategy.asset(), event, UNDERLYING).id;

  let vaultToken = createERC20TokenAsset(event.params.vault, event, VAULT_SHARE);
  vault.vaultToken = vaultToken.id;
  vaultToken.vaultAddress = event.params.vault;
  vaultToken.underlying = vault.asset;
  vaultToken.save();

  // These will be listed on approval
  vault.withdrawRequestManagers = [];

  vault.save();

  VaultTemplate.create(event.params.vault);
}

export function handleWithdrawRequestManagerSet(
  event: WithdrawRequestManagerSet
): void {
  const id = event.params.withdrawRequestManager.toHexString();
  let withdrawRequestManager = WithdrawRequestManager.load(id);
  if (!withdrawRequestManager) {
    withdrawRequestManager = new WithdrawRequestManager(id);
    withdrawRequestManager.firstUpdateBlockNumber = event.block.number;
    withdrawRequestManager.firstUpdateTimestamp = event.block.timestamp.toI32();
    withdrawRequestManager.firstUpdateTransactionHash = event.transaction.hash;
  }

  withdrawRequestManager.lastUpdateBlockNumber = event.block.number;
  withdrawRequestManager.lastUpdateTimestamp = event.block.timestamp.toI32();
  withdrawRequestManager.lastUpdateTransactionHash = event.transaction.hash;

  let w = IWithdrawRequestManager.bind(event.params.withdrawRequestManager);
  withdrawRequestManager.yieldToken = createERC20TokenAsset(w.YIELD_TOKEN(), event, UNDERLYING).id;
  withdrawRequestManager.withdrawToken = createERC20TokenAsset(w.WITHDRAW_TOKEN(), event, UNDERLYING).id;
  withdrawRequestManager.stakingToken = createERC20TokenAsset(w.STAKING_TOKEN(), event, UNDERLYING).id;

  withdrawRequestManager.save();

  WithdrawRequestManagerTemplate.create(event.params.withdrawRequestManager);
}


// export function handleFeeReceiverTransferred(
//   event: FeeReceiverTransferred
// ): void {}

// export function handlePauseAdminTransferred(
//   event: PauseAdminTransferred
// ): void {}

// export function handlePendingPauseAdminSet(event: PendingPauseAdminSet): void {}

// export function handlePendingUpgradeAdminSet(
//   event: PendingUpgradeAdminSet
// ): void {}

// export function handleUpgradeAdminTransferred(
//   event: UpgradeAdminTransferred
// ): void {}
