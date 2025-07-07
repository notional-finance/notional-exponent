import { BigInt, Bytes } from "@graphprotocol/graph-ts"
import {
  AddressRegistry,
  AccountPositionCleared,
  AccountPositionCreated,
  FeeReceiverTransferred,
  LendingRouterSet,
  PauseAdminTransferred,
  PendingPauseAdminSet,
  PendingUpgradeAdminSet,
  UpgradeAdminTransferred,
  WhitelistedVault,
  WithdrawRequestManagerSet
} from "../generated/AddressRegistry/AddressRegistry"
import { Account } from "../generated/schema"

export function handleAccountPositionCleared(
  event: AccountPositionCleared
): void { }

export function handleAccountPositionCreated(
  event: AccountPositionCreated
): void {
  const id = event.params.account.toHexString();
  let account = Account.load(id);
  if (!account) {
    account = new Account(id);
    account.firstUpdateBlockNumber = event.block.number;
    account.firstUpdateTimestamp = event.block.timestamp.toI32();
    account.firstUpdateTransactionHash = event.transaction.hash;
  }

  account.lastUpdateBlockNumber = event.block.number;
  account.lastUpdateTimestamp = event.block.timestamp.toI32();
  account.lastUpdateTransactionHash = event.transaction.hash;
  account.systemAccountType = 'None';

  account.save();
}

export function handleLendingRouterSet(event: LendingRouterSet): void {}

export function handleWhitelistedVault(event: WhitelistedVault): void {}

export function handleWithdrawRequestManagerSet(
  event: WithdrawRequestManagerSet
): void {}


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
