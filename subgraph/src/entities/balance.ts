import { ethereum, BigInt, log, Address } from "@graphprotocol/graph-ts";
import { Account, Balance, BalanceSnapshot, ProfitLossLineItem, Token } from "../../generated/schema";
import { DEFAULT_PRECISION, VAULT_DEBT, VAULT_SHARE, ZERO_ADDRESS } from "../constants";
import { ILendingRouter } from "../../generated/templates/LendingRouter/ILendingRouter";
import { IERC20Metadata } from "../../generated/AddressRegistry/IERC20Metadata";
import { IYieldStrategy } from "../../generated/AddressRegistry/IYieldStrategy";

export function getBalanceSnapshot(balance: Balance, event: ethereum.Event): BalanceSnapshot {
  let id = balance.id + ":" + event.block.number.toString();
  let snapshot = BalanceSnapshot.load(id);

  if (snapshot == null) {
    snapshot = new BalanceSnapshot(id);
    snapshot.balance = balance.id;
    snapshot.blockNumber = event.block.number;
    snapshot.timestamp = event.block.timestamp.toI32();
    snapshot.transactionHash = event.transaction.hash;

    // These features are calculated at each update to the snapshot
    snapshot.currentBalance = BigInt.zero();
    snapshot.previousBalance = BigInt.zero();
    snapshot.adjustedCostBasis = BigInt.zero();
    snapshot.currentProfitAndLossAtSnapshot = BigInt.zero();
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
        snapshot._accumulatedBalance = BigInt.zero();
        snapshot._accumulatedCostRealized = BigInt.zero();
        snapshot._lastInterestAccumulator = BigInt.zero();
        snapshot.impliedFixedRate = null;
      } else {
        snapshot._accumulatedBalance = prevSnapshot._accumulatedBalance;
        snapshot._accumulatedCostRealized = prevSnapshot._accumulatedCostRealized;
        snapshot._lastInterestAccumulator = prevSnapshot._lastInterestAccumulator;
        snapshot.impliedFixedRate = prevSnapshot.impliedFixedRate;
      }

      if (prevSnapshot) {
        // These values are always copied from the previous snapshot
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

export function setProfitLossLineItem(
  account: Account,
  token: Token,
  underlyingToken: Token,
  tokenAmount: BigInt,
  underlyingAmountRealized: BigInt,
  spotPrice: BigInt,
  lineItemType: string,
  event: ethereum.Event
): void {
  let id = event.transaction.hash.toHex() + ":" +
    event.logIndex.toString() + ":" + token.id;

  let lineItem = new ProfitLossLineItem(id);
  lineItem.blockNumber = event.block.number;
  lineItem.timestamp = event.block.timestamp.toI32();
  lineItem.transactionHash = event.transaction.hash;
  lineItem.token = token.id;
  lineItem.account = account.id;
  lineItem.underlyingToken = underlyingToken.id;

  lineItem.tokenAmount = tokenAmount;
  lineItem.underlyingAmountRealized = underlyingAmountRealized;
  // Oracle price for the underlying token
  lineItem.underlyingAmountSpot = tokenAmount
    .times(spotPrice)
    .times(underlyingToken.precision)
    .div(token.precision)
    .div(DEFAULT_PRECISION);
  lineItem.spotPrice = spotPrice;

  if (tokenAmount.gt(BigInt.zero())) {
    lineItem.realizedPrice = underlyingAmountRealized
        .times(token.precision).div(tokenAmount);
  } else {
    lineItem.realizedPrice = BigInt.zero();
  }

  lineItem.lineItemType = lineItemType;

  let snapshot = updateBalance(token, account, event.address, event);
  lineItem.balanceSnapshot = snapshot.id;

  lineItem.save();

  updateSnapshotMetrics(token, snapshot, lineItem);
}

function updateBalance(
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
    token.vaultAddress !== null
  ) {
    if (lendingRouter == ZERO_ADDRESS) {
      // Get the balance using the native balance on the vault
      let v = IERC20Metadata.bind(token.vaultAddress as Address);
      snapshot.currentBalance = v.balanceOf(accountAddress);
    } else {
      let l = ILendingRouter.bind(lendingRouter);
      snapshot.currentBalance = l.balanceOfCollateral(accountAddress, token.vaultAddress as Address);
    }
  } else if (token.tokenType == VAULT_DEBT && token.vaultAddress !== null) {
    if (lendingRouter == ZERO_ADDRESS) {
      snapshot.currentBalance = BigInt.zero();
    } else {
      let l = ILendingRouter.bind(lendingRouter);
      snapshot.currentBalance = l.balanceOfBorrowShares(accountAddress, token.vaultAddress as Address);
    }
  }

  balance.save();
  return snapshot;
}

function updateSnapshotMetrics(
  token: Token,
  snapshot: BalanceSnapshot,
  lineItem: ProfitLossLineItem
): void {
  // We use accumulated balance to calculate the inter-transaction balance
  // in case there are multiple balance changes in the same transaction.
  snapshot._accumulatedBalance = snapshot._accumulatedBalance.plus(lineItem.tokenAmount);

  // This is the total realized cost of the balance in the underlying (i.e. asset token)
  snapshot._accumulatedCostRealized = snapshot._accumulatedCostRealized.plus(lineItem.underlyingAmountRealized);

  // This is the average cost basis of the balance in the underlying token precision
  snapshot.adjustedCostBasis = snapshot._accumulatedCostRealized.times(token.precision).div(snapshot._accumulatedBalance);

  // This is the current profit and loss of the balance at the snapshot using
  // the oracle price of the token balance.
  // (_accumulatedBalance * oraclePrice) - _accumulatedCostRealized
  snapshot.currentProfitAndLossAtSnapshot = snapshot._accumulatedBalance
    .times(lineItem.spotPrice)
    .div(DEFAULT_PRECISION) // oracle rate is in default precision
    .minus(snapshot._accumulatedCostRealized);

  if (token.tokenType == VAULT_SHARE) {
    let v = IYieldStrategy.bind(token.vaultAddress as Address);

    // This is the value of one vault share in the underlying token.
    let interestAccumulator = v.convertToAssets(DEFAULT_PRECISION);

    // This is the number of yield tokens per vault share, it is decreasing over time.
    let yieldTokensPerVaultShare = v.convertSharesToYieldToken(DEFAULT_PRECISION);
    // Converts the number of yield tokens paid in fees per vault share to a vault share
    // basis so that we have a consistent value to compare to the previous snapshot.
    let vaultSharesPaidInFees = v.try_convertYieldTokenToShares(
      snapshot._lastVaultFeeAccumulator.minus(yieldTokensPerVaultShare)
    );
    let vaultFeeAccumulator = BigInt.zero();
    if (!vaultSharesPaidInFees.reverted) {
      // This can revert on zero yield token balance held
      vaultFeeAccumulator = vaultSharesPaidInFees.value;
    }

    let interestAccrued: BigInt;
    let vaultFeesAccrued: BigInt;
    if (lineItem.tokenAmount.gt(BigInt.zero())) {
      // vault share increase
      interestAccrued = interestAccumulator.minus(snapshot._lastInterestAccumulator)
          .times(snapshot._accumulatedBalance)
          .div(DEFAULT_PRECISION);
      vaultFeesAccrued = vaultFeeAccumulator
        .times(snapshot._accumulatedBalance)
        .div(DEFAULT_PRECISION);
    } else {
      // We cannot have a vault share decrease without a previous snapshot
      let prevSnapshot: BalanceSnapshot | null = null;
      if (snapshot.previousSnapshot === null) log.error("Previous snapshot not found", []);
      else {
        prevSnapshot = BalanceSnapshot.load(snapshot.previousSnapshot as string);
      }
      if (prevSnapshot === null) log.error("Previous snapshot not found", []);

      // vault share decrease
      interestAccrued = (interestAccumulator.minus(snapshot._lastInterestAccumulator))
        .times(snapshot._accumulatedBalance)
        .times(token.precision)
        .div(prevSnapshot!._accumulatedBalance)
        .div(DEFAULT_PRECISION);

      vaultFeesAccrued = (vaultFeeAccumulator.minus(snapshot._lastVaultFeeAccumulator))
        .times(snapshot._accumulatedBalance)
        .times(token.precision)
        .div(prevSnapshot!._accumulatedBalance)
        .div(DEFAULT_PRECISION);
    }

    // This accumulator is in the underlying basis.
    snapshot.totalInterestAccrualAtSnapshot = snapshot.totalInterestAccrualAtSnapshot.plus(interestAccrued);
    // This accumulator is in a vault share basis.
    snapshot.totalVaultFeesAtSnapshot = snapshot.totalVaultFeesAtSnapshot.plus(vaultFeesAccrued);
    snapshot._lastInterestAccumulator = interestAccumulator;
    snapshot._lastVaultFeeAccumulator = vaultFeeAccumulator;
  } else if (token.tokenType == VAULT_DEBT) {
    if (token.maturity === null) {
      // Variable debt
      // This accumulator is in the underlying basis.
      snapshot.totalInterestAccrualAtSnapshot = snapshot.currentProfitAndLossAtSnapshot;
    } else {
      // Fixed debt
      //  += _lastInterestAccumulator * (currentSnapshot.timestamp - previousSnapshot.timestamp) (fixed debt)
      // Set the new interest accumulator
      //  = _lastInterestAccumulator + (impliedFixedRate  * underlyingAmountRealized / RATE_PRECISION) (fixed debt)
    }
  }

  // snapshot.impliedFixedRate = null
  //   = (prevImpliedFixedRate * _accumulatedBalance + tokenAmount * (impliedFixedRate - prevImpliedFixedRate))
  //      / _accumulatedBalance

  // snapshot.incentiveSnapshots = []
  // totalClaimed += incentivesClaimed
  // adjustedClaimed += incentivesClaimed (vault share increase)

  // on vault share decrease apply this adjustment after the above line
  // adjustedClaimed = adjustedClaimed - (prevBalance - currentBalance) * adjustedClaimed / prevBalance
  // fxAdjustedClaimed += adjustedClaimed * oracleRate

  snapshot.save();
}