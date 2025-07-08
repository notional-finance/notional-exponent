import { ethereum, BigInt, log, Address } from "@graphprotocol/graph-ts";
import { Account, Balance, BalanceSnapshot, Token } from "../../generated/schema";
import { VAULT_DEBT, VAULT_SHARE, ZERO_ADDRESS } from "../constants";
import { ILendingRouter } from "../../generated/templates/LendingRouter/ILendingRouter";
import { IERC20Metadata } from "../../generated/AddressRegistry/IERC20Metadata";

export function getBalanceSnapshot(balance: Balance, event: ethereum.Event): BalanceSnapshot {
  let id = balance.id + ":" + event.block.number.toString();
  let snapshot = BalanceSnapshot.load(id);

  if (snapshot == null) {
    snapshot = new BalanceSnapshot(id);
    snapshot.balance = balance.id;
    snapshot.blockNumber = event.block.number;
    snapshot.timestamp = event.block.timestamp.toI32();
    snapshot.transaction = event.transaction.hash.toHexString();

    // These features are calculated at each update to the snapshot
    snapshot.currentBalance = BigInt.zero();
    snapshot.previousBalance = BigInt.zero();
    snapshot.adjustedCostBasis = BigInt.zero();
    snapshot.currentProfitAndLossAtSnapshot = BigInt.zero();
    snapshot.totalProfitAndLossAtSnapshot = BigInt.zero();
    snapshot.totalILAndFeesAtSnapshot = BigInt.zero();
    snapshot.totalInterestAccrualAtSnapshot = BigInt.zero();
    snapshot._accumulatedBalance = BigInt.zero();
    snapshot._accumulatedCostRealized = BigInt.zero();
    snapshot._lastInterestAccumulator = BigInt.zero();

    // These features are accumulated over the lifetime of the balance, as long
    // as it is not zero.
    if (balance.get("current") !== null) {
      let prevSnapshot = BalanceSnapshot.load(balance.current);
      if (!prevSnapshot) {
        log.error("Previous snapshot not found", []);
      } else if (prevSnapshot.currentBalance.isZero()) {
        // Reset these to zero if the previous balance is zero
        snapshot.totalILAndFeesAtSnapshot = BigInt.zero();
        snapshot._accumulatedBalance = BigInt.zero();
        snapshot._accumulatedCostRealized = BigInt.zero();
        snapshot._lastInterestAccumulator = BigInt.zero();
        snapshot.impliedFixedRate = null;
      } else {
        snapshot.totalILAndFeesAtSnapshot = prevSnapshot.totalILAndFeesAtSnapshot;
        snapshot._accumulatedBalance = prevSnapshot._accumulatedBalance;
        snapshot._accumulatedCostRealized = prevSnapshot._accumulatedCostRealized;
        snapshot._lastInterestAccumulator = prevSnapshot._lastInterestAccumulator;
        snapshot.impliedFixedRate = prevSnapshot.impliedFixedRate;
      }

      if (prevSnapshot) {
        // These values are always copied from the previous snapshot
        snapshot.totalProfitAndLossAtSnapshot = prevSnapshot.totalProfitAndLossAtSnapshot;
        snapshot.previousBalance = prevSnapshot.currentBalance;
        snapshot.adjustedCostBasis = prevSnapshot.adjustedCostBasis;
        snapshot.previousSnapshot = prevSnapshot.id;
      }
    }

    // When a new snapshot is created, it is set to the current.
    balance.current = snapshot.id;
    balance.save();
  }

  return snapshot;
}

export function getBalance(account: Account, token: Token, event: ethereum.Event): Balance {
  let id = account.id + ":" + token.id;
  let entity = Balance.load(id);

  if (entity == null) {
    entity = new Balance(id);
    entity.token = token.id;
    entity.account = account.id;
    entity.firstUpdateBlockNumber = event.block.number;
    entity.firstUpdateTimestamp = event.block.timestamp.toI32();
    entity.firstUpdateTransactionHash = event.transaction.hash;
  }

  entity.lastUpdateBlockNumber = event.block.number;
  entity.lastUpdateTimestamp = event.block.timestamp.toI32();
  entity.lastUpdateTransactionHash = event.transaction.hash;
  return entity as Balance;
}

function _saveBalance(balance: Balance, snapshot: BalanceSnapshot): void {
  balance.save();
  snapshot.save();
}

export function updateAccount(
  token: Token,
  account: Account,
  lendingRouter: Address,
  event: ethereum.Event
): BalanceSnapshot {
  let accountAddress = Address.fromBytes(Address.fromHexString(account.id));
  let balance = getBalance(account, token, event);
  let snapshot = getBalanceSnapshot(balance, event);

  if (
    token.tokenType == VAULT_SHARE &&
    token.vaultAddress != null
  ) {
    if (lendingRouter == ZERO_ADDRESS) {
      // Get the balance using the native balance on the vault
      let v = IERC20Metadata.bind(token.vaultAddress);
      snapshot.currentBalance = v.balanceOf(accountAddress);
    } else {
      let l = ILendingRouter.bind(lendingRouter);
      snapshot.currentBalance = l.balanceOfCollateral(accountAddress, token.vaultAddress);
    }
  } else if (token.tokenType == VAULT_DEBT && token.vaultAddress != null) {
    if (lendingRouter == ZERO_ADDRESS) {
      snapshot.currentBalance = BigInt.zero();
    } else {
      let l = ILendingRouter.bind(lendingRouter);
      // TODO: this is not the share value....
      snapshot.currentBalance = l.healthFactor(accountAddress, token.vaultAddress).getBorrowed();
    }
  }

  _saveBalance(balance, snapshot);

  // TODO: need to update these factors:
  // snapshot._accumulatedBalance = BigInt.zero();
  //  = _accumulatedBalance + tokenAmount

  // snapshot._accumulatedCostRealized = BigInt.zero();
  //  = _accumulatedCostRealized + underlyingAmountRealized

  // snapshot.adjustedCostBasis = BigInt.zero();
  //  = _accumulatedCostRealized / _accumulatedBalance

  // * Can be aggregate
  // snapshot.currentProfitAndLossAtSnapshot = BigInt.zero();
  //  =  (_accumulatedBalance * oraclePrice) - (adjustedCostBasis * _accumulatedBalance)

  // * Can be aggregate
  // snapshot.totalProfitAndLossAtSnapshot = BigInt.zero();
  //  = (_accumulatedBalance * oraclePrice) - _accumulatedCostRealized

  // * Can be aggregate (maybe?)
  // snapshot.totalInterestAccrualAtSnapshot = BigInt.zero();
  //  += (latestRate - _lastInterestAccumulator) * currentBalance / prevBalance (vault share decrease)
  //  += (latestRate - _lastInterestAccumulator) * prevBalance (vault share increase)
  //  += _lastInterestAccumulator * (currentSnapshot.timestamp - previousSnapshot.timestamp) (fixed debt)
  //  = currentProfitAndLossAtSnapshot (variable debt)

  // * Can be aggregate (maybe?)
  // snapshot.totalVaultFeesAtSnapshot = BigInt.zero();
  //  += (latestRate - _lastInterestAccumulator) * currentBalance / prevBalance (vault share decrease)
  //  += (latestRate - _lastInterestAccumulator) * prevBalance (vault share increase)
  // (latestRate is the vault share to yield token rate)

  // snapshot._lastInterestAccumulator = BigInt.zero();
  //   = lastOracleValue (vault shares)
  //   = _lastInterestAccumulator + (impliedFixedRate  * underlyingAmountRealized / RATE_PRECISION) (fixed debt)

  // snapshot.impliedFixedRate = null
  //   = (prevImpliedFixedRate * _accumulatedBalance + tokenAmount * (impliedFixedRate - prevImpliedFixedRate))
  //      / _accumulatedBalance

  // snapshot.incentiveSnapshots = []
  // totalClaimed += incentivesClaimed
  // adjustedClaimed += incentivesClaimed (vault share increase)

  // on vault share decrease apply this adjustment after the above line
  // adjustedClaimed = adjustedClaimed - (prevBalance - currentBalance) * adjustedClaimed / prevBalance

  return snapshot;
}

