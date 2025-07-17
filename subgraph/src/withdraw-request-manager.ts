import { ethereum, store, Address, BigInt } from "@graphprotocol/graph-ts";
import {
  ApprovedVault,
  InitiateWithdrawRequest,
  IWithdrawRequestManager,
  WithdrawRequestTokenized,
} from "../generated/templates/WithdrawRequestManager/IWithdrawRequestManager";
import { TokenizedWithdrawRequest, Vault, WithdrawRequest } from "../generated/schema";
import { getBalance, getBalanceSnapshot, updateSnapshotMetrics } from "./entities/balance";
import { getToken } from "./entities/token";
import { loadAccount } from "./entities/account";
import { convertPrice } from "./lending-router";
import { IYieldStrategy } from "../generated/templates/WithdrawRequestManager/IYieldStrategy";

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
  }
  withdrawRequest.lastUpdateBlockNumber = event.block.number;
  withdrawRequest.lastUpdateTimestamp = event.block.timestamp.toI32();
  withdrawRequest.lastUpdateTransactionHash = event.transaction.hash;

  return withdrawRequest;
}

export function handleApprovedVault(event: ApprovedVault): void {
  let vault = Vault.load(event.params.vault.toHexString());
  if (!vault) return;

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

function updateBalanceSnapshotForWithdrawRequest(w: WithdrawRequest, event: ethereum.Event): void {
  let vaultShare = getToken(w.vault);
  let account = loadAccount(w.account, event);
  let balance = getBalance(account, vaultShare, event);
  let snapshot = getBalanceSnapshot(balance, event);
  snapshot.previousBalance = snapshot.currentBalance;
  snapshot.save();

  let underlying = getToken(vaultShare.underlying!);
  let price = convertPrice(
    IYieldStrategy.bind(Address.fromString(w.vault)).price1(Address.fromString(w.account)),
    underlying,
  );
  updateSnapshotMetrics(vaultShare, underlying, snapshot, BigInt.zero(), BigInt.zero(), price, balance, event);
  snapshot.save();

  // Set this at the end to stop any further interest accruals
  balance.withdrawRequest = w.id;
  balance.save();
}

export function handleInitiateWithdrawRequest(event: InitiateWithdrawRequest): void {
  let withdrawRequest = getWithdrawRequest(event.address, event.params.vault, event.params.account, event);
  withdrawRequest.requestId = event.params.requestId;
  withdrawRequest.yieldTokenAmount = event.params.yieldTokenAmount;
  withdrawRequest.sharesAmount = event.params.sharesAmount;
  withdrawRequest.save();

  updateBalanceSnapshotForWithdrawRequest(withdrawRequest, event);
}

export function handleWithdrawRequestTokenized(event: WithdrawRequestTokenized): void {
  let id = event.address.toHexString() + ":" + event.params.requestId.toString();
  let twr = TokenizedWithdrawRequest.load(id);
  if (!twr) {
    twr = new TokenizedWithdrawRequest(id);
  }
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
  twr.save();

  // Update the withdraw requests
  let toWithdrawRequest = getWithdrawRequest(event.address, event.params.vault, event.params.to, event);
  toWithdrawRequest.requestId = event.params.requestId;
  toWithdrawRequest.yieldTokenAmount = toW.getW().yieldTokenAmount;
  toWithdrawRequest.sharesAmount = toW.getW().sharesAmount;
  toWithdrawRequest.tokenizedWithdrawRequest = twr.id;
  toWithdrawRequest.save();
  updateBalanceSnapshotForWithdrawRequest(toWithdrawRequest, event);

  // Update the from withdraw request
  let fromWithdrawRequest = getWithdrawRequest(event.address, event.params.vault, event.params.from, event);
  let fromW = m.getWithdrawRequest(event.params.vault, event.params.from);
  if (fromW.getW().requestId.isZero()) {
    // delete the from withdraw request
    store.remove("WithdrawRequest", fromWithdrawRequest.id);
    let account = loadAccount(event.params.from.toHexString(), event);
    let vaultShare = getToken(event.params.vault.toHexString());
    let balance = getBalance(account, vaultShare, event);
    // Clear the withdraw request if it is removed
    balance.withdrawRequest = null;
    balance.save();
  } else {
    fromWithdrawRequest.requestId = event.params.requestId;
    fromWithdrawRequest.yieldTokenAmount = fromW.getW().yieldTokenAmount;
    fromWithdrawRequest.sharesAmount = fromW.getW().sharesAmount;
    fromWithdrawRequest.tokenizedWithdrawRequest = twr.id;
    fromWithdrawRequest.save();
  }
}
