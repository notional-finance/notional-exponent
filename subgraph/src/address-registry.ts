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
import { createToken } from "./entities/token"
import { createAccount } from "./entities/account"

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

  vault.lastUpdateBlockNumber = event.block.number;
  vault.lastUpdateTimestamp = event.block.timestamp.toI32();
  vault.lastUpdateTransactionHash = event.transaction.hash;

  let yieldStrategy = IYieldStrategy.bind(event.params.vault);
  vault.feeRate = yieldStrategy.feeRate();
  vault.yieldToken = createToken(yieldStrategy.yieldToken().toHexString());
  vault.asset = createToken(yieldStrategy.asset().toHexString());
  vault.vaultToken = createToken(event.params.vault.toHexString());
  // These will be listed on approval
  vault.withdrawRequestManagers = [];

  vault.save();
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
  withdrawRequestManager.yieldToken = createToken(w.YIELD_TOKEN().toHexString());
  withdrawRequestManager.withdrawToken = createToken(w.WITHDRAW_TOKEN().toHexString());
  withdrawRequestManager.stakingToken = createToken(w.STAKING_TOKEN().toHexString());

  withdrawRequestManager.save();
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
