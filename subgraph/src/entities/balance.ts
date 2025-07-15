import { ethereum, BigInt, log, Address } from "@graphprotocol/graph-ts";
import { Account, Balance, BalanceSnapshot, IncentiveSnapshot, ProfitLossLineItem, Token } from "../../generated/schema";
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

export function createSnapshotForIncentives(
  account: Account,
  vaultAddress: Address,
  rewardToken: Address,
  amount: BigInt,
  event: ethereum.Event
): void {
  let balanceId = account.id + ":" + vaultAddress.toHexString();
  let balance = Balance.load(balanceId);
  if (balance === null) return;

  let snapshot = getBalanceSnapshot(balance, event);
  let id = snapshot.id + ":" + rewardToken.toHexString();

  let incentiveSnapshot = new IncentiveSnapshot(id);
  incentiveSnapshot.blockNumber = snapshot.blockNumber;
  incentiveSnapshot.timestamp = snapshot.timestamp;
  incentiveSnapshot.transactionHash = snapshot.transactionHash;
  incentiveSnapshot.balanceSnapshot = snapshot.id;
  incentiveSnapshot.rewardToken = rewardToken.toHexString();

  incentiveSnapshot.totalClaimed = BigInt.zero();
  incentiveSnapshot.adjustedClaimed = BigInt.zero();

  if (snapshot.previousSnapshot) {
    let prevSnapshot = IncentiveSnapshot.load(
      (snapshot.previousSnapshot as string) + ":" + rewardToken.toHexString()
    );

    if (prevSnapshot) {
      incentiveSnapshot.totalClaimed = prevSnapshot.totalClaimed;
      incentiveSnapshot.adjustedClaimed = prevSnapshot.adjustedClaimed;
    }
  }

  incentiveSnapshot.totalClaimed = incentiveSnapshot.totalClaimed.plus(amount);
  incentiveSnapshot.adjustedClaimed = incentiveSnapshot.adjustedClaimed.plus(amount);
  if (snapshot.currentBalance.lt(snapshot.previousBalance)) {
    // On vault share decrease apply this adjustment after the above line
    // adjustedClaimed = adjustedClaimed - (prevBalance - currentBalance) * adjustedClaimed / prevBalance
    incentiveSnapshot.adjustedClaimed = incentiveSnapshot.adjustedClaimed.minus(
      snapshot.previousBalance.minus(snapshot.currentBalance)
      .times(incentiveSnapshot.adjustedClaimed).div(snapshot.previousBalance)
    );
  }

  incentiveSnapshot.save();
}

export function createTradeExecutionLineItem(
  account: Account,
  vaultAddress: Address,
  sellToken: Token,
  buyToken: Token,
  sellAmount: BigInt,
  buyAmount: BigInt,
  logIndex: BigInt,
  event: ethereum.Event
): void {
  let id = event.transaction.hash.toHex() + ":" + logIndex.toString() + ":" + sellToken.id;

  let lineItem = new ProfitLossLineItem(id);
  lineItem.blockNumber = event.block.number;
  lineItem.timestamp = event.block.timestamp.toI32();
  lineItem.transactionHash = event.transaction.hash;
  lineItem.token = sellToken.id;
  lineItem.account = account.id;
  lineItem.underlyingToken = buyToken.id;

  lineItem.tokenAmount = sellAmount;
  lineItem.underlyingAmountRealized = buyAmount;
  // Spot prices are not known on chain for trades
  lineItem.underlyingAmountSpot = BigInt.zero();
  lineItem.spotPrice = BigInt.zero();

  if (sellAmount.gt(BigInt.zero())) {
    lineItem.realizedPrice = buyAmount
        .times(sellToken.precision).div(sellAmount);
  } else {
    lineItem.realizedPrice = BigInt.zero();
  }

  lineItem.lineItemType = "TradeExecution";

  let balanceId = account.id + ":" + vaultAddress.toHexString();
  let balance = Balance.load(balanceId);
  if (balance === null) return;

  let snapshot = getBalanceSnapshot(balance, event);
  lineItem.balanceSnapshot = snapshot.id;
  lineItem.save();
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
  snapshot.save();
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
  snapshot.save();

  return snapshot;
}

function updateSnapshotMetrics(
  token: Token,
  snapshot: BalanceSnapshot,
  lineItem: ProfitLossLineItem
): void {

  if (token.tokenType == VAULT_SHARE) {
    let v = IYieldStrategy.bind(token.vaultAddress as Address);

    // This is the value of one vault share in the underlying token.
    // the problem is that this includes both interest accrued as well as some
    // aspects of mark to market pnl.
    // TODO: fix the below
    // For staking tokens we use the withdraw request manager to get the exchange rate
    // For Pendle PT we use the PT accounting asset to get the exchange rate and the
    // token in amount to set the implied fixed rate
    // For LP tokens we just default to convertToAssets to get the interest accrual but
    // we will need to do it some other way off chain.
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

    // This accumulator is in the underlying basis.
    let interestAccruedSinceLastSnapshot = interestAccumulator.minus(snapshot._lastInterestAccumulator)
          .times(snapshot._accumulatedBalance)
          .div(DEFAULT_PRECISION);
    // This accumulator is in a vault share basis.
    let vaultFeesAccruedSinceLastSnapshot = vaultFeeAccumulator
        .times(snapshot._accumulatedBalance)
        .div(DEFAULT_PRECISION);

    snapshot.totalInterestAccrualAtSnapshot = snapshot.totalInterestAccrualAtSnapshot
      .plus(interestAccruedSinceLastSnapshot);
    snapshot.totalVaultFeesAtSnapshot = snapshot.totalVaultFeesAtSnapshot
      .plus(vaultFeesAccruedSinceLastSnapshot);
    snapshot._lastInterestAccumulator = interestAccumulator;
    snapshot._lastVaultFeeAccumulator = vaultFeeAccumulator;

    // It shouldn't be possible to have a vault share decrease without a previous balance
    if (lineItem.tokenAmount.lt(BigInt.zero()) && snapshot.previousBalance.gt(BigInt.zero())) {
      // Calculate an adjustment to the total interest accrued that is proportional
      // to the remaining balance. Use the current and previous balances to get the final
      // balance after the transaction.
      snapshot.totalInterestAccrualAtSnapshot = snapshot.totalInterestAccrualAtSnapshot
        .times(snapshot.currentBalance)
        .div(snapshot.previousBalance)
     
      snapshot.totalVaultFeesAtSnapshot = snapshot.totalVaultFeesAtSnapshot
        .times(snapshot.currentBalance)
        .div(snapshot.previousBalance)
    }

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

  // Update all these accumulators after the interest accrual is calculated

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
}