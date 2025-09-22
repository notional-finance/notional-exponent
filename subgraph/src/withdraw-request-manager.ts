import { ethereum, store, Address, BigInt, log } from "@graphprotocol/graph-ts";
import {
  ApprovedVault,
  InitiateWithdrawRequest,
  IWithdrawRequestManager,
  WithdrawRequestFinalized,
  WithdrawRequestTokenized,
} from "../generated/templates/WithdrawRequestManager/IWithdrawRequestManager";
import { TokenizedWithdrawRequest, Vault, WithdrawRequest } from "../generated/schema";
import {
  createWithdrawRequestFinalizedLineItem,
  createWithdrawRequestLineItem,
  getBalance,
  getBalanceSnapshot,
  updateSnapshotMetrics,
} from "./entities/balance";
import { createERC20TokenAsset, getToken } from "./entities/token";
import { loadAccount } from "./entities/account";
import { convertPrice } from "./lending-router";
import { IYieldStrategy } from "../generated/templates/WithdrawRequestManager/IYieldStrategy";
import { UNDERLYING } from "./constants";
import { createVault } from "./address-registry";

function getWithdrawRequest(
  withdrawRequestManager: Address,
  vault: Address,
  account: Address,
  event: ethereum.Event,
): WithdrawRequest {
  let id = withdrawRequestManager.toHexString() + ":" + vault.toHexString() + ":" + account.toHexString();
  let withdrawRequest = WithdrawRequest.load(id);
  if (!withdrawRequest) {
    withdrawRequest = new WithdrawRequest(id);
    withdrawRequest.withdrawRequestManager = event.address.toHexString();
    withdrawRequest.account = account.toHexString();
    withdrawRequest.vault = vault.toHexString();
    withdrawRequest.balance = account.toHexString() + ":" + vault.toHexString();
    withdrawRequest.yieldTokenAmount = BigInt.zero();
    withdrawRequest.sharesAmount = BigInt.zero();
  }
  withdrawRequest.lastUpdateBlockNumber = event.block.number;
  withdrawRequest.lastUpdateTimestamp = event.block.timestamp.toI32();
  withdrawRequest.lastUpdateTransactionHash = event.transaction.hash;

  return withdrawRequest;
}

export function handleApprovedVault(event: ApprovedVault): void {
  // Create the vault if it is approved before being whitelisted
  let vault = Vault.load(event.params.vault.toHexString());
  if (!vault) {
    vault = createVault(event.params.vault, event, false);
  }

  let managers = vault.withdrawRequestManagers;
  if (event.params.isApproved) {
    managers.push(event.address.toHexString());
  } else {
    let index = managers.indexOf(event.address.toHexString());
    if (index !== -1) {
      managers.splice(index, 1);
    }
  }
  vault.withdrawRequestManagers = managers;
  vault.save();
}

function updateBalanceSnapshotForWithdrawRequest(
  w: WithdrawRequest,
  sharesAmount: BigInt,
  yieldTokenAmount: BigInt,
  event: ethereum.Event,
): void {
  let vaultShare = getToken(w.vault);
  let account = loadAccount(w.account, event);
  let balance = getBalance(account, vaultShare, event);
  let snapshot = getBalanceSnapshot(balance, event);

  snapshot.currentBalance = snapshot.previousBalance;
  snapshot.save();

  createWithdrawRequestLineItem(
    account,
    Address.fromBytes(vaultShare.vaultAddress!),
    sharesAmount,
    yieldTokenAmount,
    snapshot.id,
    event,
  );

  // If the accumulated balance is zero then we will get divide by zero errors when we go to update
  // the snapshot metrics. This can occur when liquidating and receiving a tokenized withdraw request
  // for the first time.
  if (snapshot._accumulatedBalance.notEqual(BigInt.fromI32(0))) {
    let underlying = getToken(vaultShare.underlying!);
    let price = convertPrice(
      IYieldStrategy.bind(Address.fromString(w.vault)).price1(Address.fromString(w.account)),
      underlying,
    );
    updateSnapshotMetrics(vaultShare, underlying, snapshot, BigInt.zero(), BigInt.zero(), price, balance, event);
    snapshot.save();
  }

  if (w.requestId.isZero()) {
    // Clear the withdraw request if it is removed
    let wr = balance.withdrawRequest;
    if (wr) {
      let index = wr.indexOf(w.id);
      if (index !== -1) {
        wr.splice(index, 1);
      }
    }
    balance.withdrawRequest = wr;
  } else {
    // Set this at the end to stop any further interest accruals
    let wr = balance.withdrawRequest;
    if (!wr) {
      wr = [w.id];
    } else if (!wr.includes(w.id)) {
      wr.push(w.id);
    }
    balance.withdrawRequest = wr;
  }
  balance.save();
}

function updateBalanceSnapshotForFinalized(
  w: WithdrawRequest,
  yieldTokenAmount: BigInt,
  withdrawTokenAmount: BigInt,
  event: ethereum.Event,
): void {
  let vaultShare = getToken(w.vault);
  let account = loadAccount(w.account, event);
  let balance = getBalance(account, vaultShare, event);
  let snapshot = getBalanceSnapshot(balance, event);
  let m = IWithdrawRequestManager.bind(event.address);
  let withdrawToken = createERC20TokenAsset(m.WITHDRAW_TOKEN(), event, UNDERLYING);

  snapshot.currentBalance = snapshot.previousBalance;
  snapshot.save();

  createWithdrawRequestFinalizedLineItem(
    account,
    Address.fromString(w.vault),
    yieldTokenAmount,
    withdrawTokenAmount,
    withdrawToken,
    snapshot.id,
    event,
  );

  // If the accumulated balance is zero then we will get divide by zero errors when we go to update
  // the snapshot metrics. This can occur when liquidating and receiving a tokenized withdraw request
  // for the first time.
  if (snapshot._accumulatedBalance.notEqual(BigInt.fromI32(0))) {
    let underlying = getToken(vaultShare.underlying!);
    let _price = IYieldStrategy.bind(Address.fromString(w.vault)).try_price1(Address.fromString(w.account));
    let price: BigInt;
    if (!_price.reverted) {
      price = convertPrice(_price.value, underlying);
    } else {
      price = BigInt.zero();
    }
    updateSnapshotMetrics(vaultShare, underlying, snapshot, BigInt.zero(), BigInt.zero(), price, balance, event);
    snapshot.save();
  }

  balance.save();
}

export function handleInitiateWithdrawRequest(event: InitiateWithdrawRequest): void {
  let withdrawRequest = getWithdrawRequest(event.address, event.params.vault, event.params.account, event);
  withdrawRequest.requestId = event.params.requestId;
  withdrawRequest.yieldTokenAmount = event.params.yieldTokenAmount;
  withdrawRequest.sharesAmount = event.params.sharesAmount;
  withdrawRequest.save();

  updateBalanceSnapshotForWithdrawRequest(
    withdrawRequest,
    event.params.sharesAmount,
    event.params.yieldTokenAmount,
    event,
  );
}

export function handleWithdrawRequestTokenized(event: WithdrawRequestTokenized): void {
  let id = event.address.toHexString() + ":" + event.params.requestId.toString();
  let twr = TokenizedWithdrawRequest.load(id);
  if (!twr) {
    twr = new TokenizedWithdrawRequest(id);
    twr._holders = [];
  }
  let holders = twr._holders;
  twr.lastUpdateBlockNumber = event.block.number;
  twr.lastUpdateTimestamp = event.block.timestamp.toI32();
  twr.lastUpdateTransactionHash = event.transaction.hash;

  twr.withdrawRequestManager = event.address.toHexString();
  let m = IWithdrawRequestManager.bind(event.address);

  // Get the tokenized withdraw request using the to address since we
  // know that it must have some value. (the from could have it deleted)
  let toW = m.getWithdrawRequest(event.params.vault, event.params.to);
  twr.totalYieldTokenAmount = toW.getS().totalYieldTokenAmount;
  twr.totalWithdraw = toW.getS().totalWithdraw;
  twr.finalized = toW.getS().finalized;

  // Update the withdraw requests
  let toWithdrawRequest = getWithdrawRequest(event.address, event.params.vault, event.params.to, event);
  let toYieldTokenAmountBefore = toWithdrawRequest.yieldTokenAmount;
  toWithdrawRequest.requestId = event.params.requestId;
  toWithdrawRequest.yieldTokenAmount = toW.getW().yieldTokenAmount;
  toWithdrawRequest.sharesAmount = toW.getW().sharesAmount;
  toWithdrawRequest.tokenizedWithdrawRequest = twr.id;
  toWithdrawRequest.save();
  if (!holders.includes(toWithdrawRequest.id)) {
    holders.push(toWithdrawRequest.id);
  }

  // This is calculated as the change in the yield token amount on the
  // to withdraw request before and after the tokenization
  let yieldTokenAmount = toWithdrawRequest.yieldTokenAmount.minus(toYieldTokenAmountBefore);
  updateBalanceSnapshotForWithdrawRequest(toWithdrawRequest, event.params.sharesAmount, yieldTokenAmount, event);

  // Update the from withdraw request
  let fromWithdrawRequest = getWithdrawRequest(event.address, event.params.vault, event.params.from, event);
  let fromW = m.getWithdrawRequest(event.params.vault, event.params.from);
  fromWithdrawRequest.requestId = event.params.requestId;
  fromWithdrawRequest.yieldTokenAmount = fromW.getW().yieldTokenAmount;
  fromWithdrawRequest.sharesAmount = fromW.getW().sharesAmount;
  fromWithdrawRequest.tokenizedWithdrawRequest = twr.id;
  fromWithdrawRequest.save();

  // Negative shares and yield token amounts because they are being transferred
  updateBalanceSnapshotForWithdrawRequest(
    fromWithdrawRequest,
    event.params.sharesAmount.neg(),
    yieldTokenAmount.neg(),
    event,
  );

  if (fromW.getW().requestId.isZero()) {
    // Remove the withdraw request if the requestId is zero
    store.remove("WithdrawRequest", fromWithdrawRequest.id);
    if (holders.includes(fromWithdrawRequest.id)) {
      holders.splice(holders.indexOf(fromWithdrawRequest.id), 1);
    }
  } else if (!holders.includes(fromWithdrawRequest.id)) {
    holders.push(fromWithdrawRequest.id);
  }

  twr._holders = holders;
  twr.save();
}

export function handleWithdrawRequestFinalized(event: WithdrawRequestFinalized): void {
  let id = event.address.toHexString() + ":" + event.params.requestId.toString();
  let twr = TokenizedWithdrawRequest.load(id);

  if (twr) {
    twr.totalWithdraw = event.params.totalWithdraw;
    twr.finalized = true;
    twr.finalizedBlockNumber = event.block.number;
    twr.finalizedTimestamp = event.block.timestamp.toI32();
    twr.finalizedTransactionHash = event.transaction.hash;
    twr.save();

    for (let i = 0; i < twr._holders.length; i++) {
      let w = WithdrawRequest.load(twr._holders[i]);
      if (w) {
        // Update all the tokenized holders with the new total withdraw amount
        let withdrawTokenAmount = w.yieldTokenAmount.times(twr.totalWithdraw).div(twr.totalYieldTokenAmount);
        updateBalanceSnapshotForFinalized(w, w.yieldTokenAmount, withdrawTokenAmount, event);
      }
    }
  } else {
    // If there is no tokenized withdraw request, then just update the balance snapshot for the account
    let w = getWithdrawRequest(event.address, event.params.vault, event.params.account, event);
    updateBalanceSnapshotForFinalized(w, w.yieldTokenAmount, event.params.totalWithdraw, event);
  }
}
