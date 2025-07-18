import { ethereum, BigInt, log, Address, ByteArray, crypto } from "@graphprotocol/graph-ts";
import {
  Account,
  Balance,
  BalanceSnapshot,
  IncentiveSnapshot,
  ProfitLossLineItem,
  Token,
} from "../../generated/schema";
import {
  DEFAULT_PRECISION,
  RATE_PRECISION,
  SECONDS_IN_YEAR,
  TRADING_MODULE,
  VAULT_DEBT,
  VAULT_SHARE,
  ZERO_ADDRESS,
} from "../constants";
import { ILendingRouter } from "../../generated/templates/LendingRouter/ILendingRouter";
import { IERC20Metadata } from "../../generated/AddressRegistry/IERC20Metadata";
import { IYieldStrategy } from "../../generated/AddressRegistry/IYieldStrategy";
import { ITradingModule } from "../../generated/AddressRegistry/ITradingModule";
import { IPPrincipalToken } from "../../generated/AddressRegistry/IPPrincipalToken";

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
    snapshot.totalVaultFeesAtSnapshot = BigInt.zero();
    snapshot._accumulatedBalance = BigInt.zero();
    snapshot._accumulatedCostRealized = BigInt.zero();
    snapshot._lastInterestAccumulator = BigInt.zero();
    snapshot._lastVaultFeeAccumulator = BigInt.zero();

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
        snapshot._lastVaultFeeAccumulator = BigInt.zero();
        snapshot.impliedFixedRate = null;
      } else {
        snapshot._accumulatedBalance = prevSnapshot._accumulatedBalance;
        snapshot._accumulatedCostRealized = prevSnapshot._accumulatedCostRealized;
        snapshot._lastInterestAccumulator = prevSnapshot._lastInterestAccumulator;
        snapshot._lastVaultFeeAccumulator = prevSnapshot._lastVaultFeeAccumulator;
        snapshot.impliedFixedRate = prevSnapshot.impliedFixedRate;
        snapshot.totalInterestAccrualAtSnapshot = prevSnapshot.totalInterestAccrualAtSnapshot;
        snapshot.totalVaultFeesAtSnapshot = prevSnapshot.totalVaultFeesAtSnapshot;
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
  event: ethereum.Event,
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
    let prevSnapshot = IncentiveSnapshot.load((snapshot.previousSnapshot as string) + ":" + rewardToken.toHexString());

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
      snapshot.previousBalance
        .minus(snapshot.currentBalance)
        .times(incentiveSnapshot.adjustedClaimed)
        .div(snapshot.previousBalance),
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
  event: ethereum.Event,
): void {
  let id = event.transaction.hash.toHex() + ":" + logIndex.toString() + ":" + account.id + ":" + sellToken.id;

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
    lineItem.realizedPrice = buyAmount.times(sellToken.precision).div(sellAmount);
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
  lendingRouter: Address,
  event: ethereum.Event,
): void {
  let id = event.transaction.hash.toHex() + ":" + event.logIndex.toString() + ":" + account.id + ":" + token.id;

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
    .div(DEFAULT_PRECISION)
    .div(token.precision);
  lineItem.spotPrice = spotPrice;

  if (tokenAmount.notEqual(BigInt.zero())) {
    // This is reported in DEFAULT_PRECISION
    lineItem.realizedPrice = underlyingAmountRealized
      .times(DEFAULT_PRECISION)
      .times(token.precision)
      .div(tokenAmount)
      .div(underlyingToken.precision);
  } else {
    lineItem.realizedPrice = BigInt.zero();
  }

  lineItem.lineItemType = lineItemType;

  let balance = getBalance(account, token, event);
  let snapshot = updateBalance(balance, token, account, lendingRouter, event);
  lineItem.balanceSnapshot = snapshot.id;

  lineItem.save();

  updateSnapshotMetrics(
    token,
    underlyingToken,
    snapshot,
    lineItem.tokenAmount,
    lineItem.underlyingAmountRealized,
    lineItem.spotPrice,
    balance,
    event,
  );
  snapshot.save();
}

function updateBalance(
  balance: Balance,
  token: Token,
  account: Account,
  lendingRouter: Address,
  event: ethereum.Event,
): BalanceSnapshot {
  let accountAddress = Address.fromBytes(Address.fromHexString(account.id));
  let snapshot = getBalanceSnapshot(balance, event);

  if (token.tokenType == VAULT_SHARE && token.vaultAddress !== null) {
    if (lendingRouter == ZERO_ADDRESS) {
      // Get the balance using the native balance on the vault
      let v = IERC20Metadata.bind(Address.fromBytes(token.vaultAddress!));
      snapshot.currentBalance = v.balanceOf(accountAddress);
    } else {
      let l = ILendingRouter.bind(lendingRouter);
      snapshot.currentBalance = l.balanceOfCollateral(accountAddress, Address.fromBytes(token.vaultAddress!));
    }
  } else if (token.tokenType == VAULT_DEBT && token.vaultAddress !== null) {
    if (lendingRouter == ZERO_ADDRESS) {
      snapshot.currentBalance = BigInt.zero();
    } else {
      let l = ILendingRouter.bind(lendingRouter);
      snapshot.currentBalance = l.balanceOfBorrowShares(accountAddress, Address.fromBytes(token.vaultAddress!));
    }
  }

  balance.save();
  snapshot.save();

  return snapshot;
}

function findPendleTokenInAmount(
  vaultAddress: Address,
  tokenInSy: Address,
  ptToken: Address,
  event: ethereum.Event,
): BigInt {
  if (event.receipt === null) return BigInt.zero();

  for (let i = 0; i < event.receipt!.logs.length; i++) {
    let _log = event.receipt!.logs[i];
    if (_log.address.toHexString() != vaultAddress.toHexString()) continue;

    if (_log.topics[0] == crypto.keccak256(ByteArray.fromUTF8("TradeExecuted(address,address,uint256,uint256)"))) {
      let sellToken = Address.fromBytes(_log.topics[1]);
      let buyToken = Address.fromBytes(_log.topics[2]);
      let sellAmount = BigInt.fromUnsignedBytes(changetype<ByteArray>(_log.data.slice(0, 32).reverse()));
      let buyAmount = BigInt.fromUnsignedBytes(changetype<ByteArray>(_log.data.slice(32).reverse()));

      if (sellToken == tokenInSy && buyToken == ptToken) {
        return sellAmount;
      } else if (sellToken == ptToken && buyToken == tokenInSy) {
        return buyAmount;
      }
    }
  }

  return BigInt.zero();
}

function getInterestAccumulator(
  v: IYieldStrategy,
  tokenAmount: BigInt,
  _lastInterestAccumulator: BigInt,
  event: ethereum.Event,
): BigInt {
  let strategy = v.strategy();
  let yieldToken = v.yieldToken();
  let accountingAsset = v.accountingAsset();
  let t = ITradingModule.bind(Address.fromBytes(TRADING_MODULE));

  if (strategy == "Staking") {
    return t.getOraclePrice(yieldToken, accountingAsset).getAnswer();
  } else if (strategy == "PendlePT") {
    let pt = IPPrincipalToken.bind(Address.fromBytes(yieldToken));
    let expiry = pt.expiry();
    let timeToExpiry = expiry.minus(event.block.timestamp);
    let x: f64 =
      (v.feeRate().times(RATE_PRECISION).times(timeToExpiry).div(DEFAULT_PRECISION).toI64() as f64) /
      (SECONDS_IN_YEAR.toI64() as f64);

    let discountFactor = BigInt.fromI64(Math.floor(Math.exp(x) * (RATE_PRECISION.toI64() as f64)) as i64);
    let marginalPtAtMaturity = tokenAmount.times(discountFactor).div(RATE_PRECISION);
    let tokenInAmount = findPendleTokenInAmount(v._address, accountingAsset, yieldToken, event);
    let marginalRemainingInterest = marginalPtAtMaturity.minus(tokenInAmount);
    return _lastInterestAccumulator.plus(marginalRemainingInterest.times(SECONDS_IN_YEAR).div(timeToExpiry));
  } else {
    // NOTE: this can go negative if the price goes down.
    return v.convertToAssets(DEFAULT_PRECISION);
  }
}

export function updateSnapshotMetrics(
  token: Token,
  underlyingToken: Token,
  snapshot: BalanceSnapshot,
  tokenAmount: BigInt,
  underlyingAmountRealized: BigInt,
  spotPrice: BigInt,
  balance: Balance,
  event: ethereum.Event,
): void {
  if (token.tokenType == VAULT_SHARE) {
    let v = IYieldStrategy.bind(Address.fromBytes(token.vaultAddress!));

    let interestAccumulator: BigInt;
    let vaultFeeAccumulator: BigInt;
    if (balance.withdrawRequest === null) {
      // This is the value of one vault share in the underlying token.
      // the problem is that this includes both interest accrued as well as some
      // aspects of mark to market pnl.
      interestAccumulator = getInterestAccumulator(v, tokenAmount, snapshot._lastInterestAccumulator, event);

      // This is the number of yield tokens per vault share, it is decreasing over time.
      // TODO: need to know the yield token decimals to do this correctly
      vaultFeeAccumulator = v.convertSharesToYieldToken(DEFAULT_PRECISION);
    } else {
      // Pause the interest accrual and vault fees accrual during a withdraw request
      interestAccumulator = snapshot._lastInterestAccumulator;
      vaultFeeAccumulator = snapshot._lastVaultFeeAccumulator;
    }

    // This accumulator is in the underlying basis.
    let interestAccruedSinceLastSnapshot = interestAccumulator
      .minus(snapshot._lastInterestAccumulator)
      .times(snapshot._accumulatedBalance)
      .div(DEFAULT_PRECISION);
    // This accumulator is in a yield token basis.
    let vaultFeesAccruedSinceLastSnapshot = snapshot._lastVaultFeeAccumulator
      .minus(vaultFeeAccumulator)
      .times(snapshot._accumulatedBalance)
      .div(DEFAULT_PRECISION);

    snapshot.totalInterestAccrualAtSnapshot = snapshot.totalInterestAccrualAtSnapshot.plus(
      interestAccruedSinceLastSnapshot,
    );
    snapshot.totalVaultFeesAtSnapshot = snapshot.totalVaultFeesAtSnapshot.plus(vaultFeesAccruedSinceLastSnapshot);
    snapshot._lastInterestAccumulator = interestAccumulator;
    snapshot._lastVaultFeeAccumulator = vaultFeeAccumulator;

    // It shouldn't be possible to have a vault share decrease without a previous balance
    if (tokenAmount.lt(BigInt.zero()) && snapshot.previousBalance.gt(BigInt.zero())) {
      // Calculate an adjustment to the total interest accrued that is proportional
      // to the remaining balance. Use the current and previous balances to get the final
      // balance after the transaction.
      snapshot.totalInterestAccrualAtSnapshot = snapshot.totalInterestAccrualAtSnapshot
        .times(snapshot.currentBalance)
        .div(snapshot.previousBalance);

      snapshot.totalVaultFeesAtSnapshot = snapshot.totalVaultFeesAtSnapshot
        .times(snapshot.currentBalance)
        .div(snapshot.previousBalance);
    }
  }

  // We use accumulated balance to calculate the inter-transaction balance
  // in case there are multiple balance changes in the same transaction.
  snapshot._accumulatedBalance = snapshot._accumulatedBalance.plus(tokenAmount);

  // This is the total realized cost of the balance in the underlying (i.e. asset token)
  snapshot._accumulatedCostRealized = snapshot._accumulatedCostRealized.plus(underlyingAmountRealized);

  // This is the average cost basis of the balance in the underlying token precision
  snapshot.adjustedCostBasis = snapshot._accumulatedCostRealized
    .times(token.precision)
    .div(snapshot._accumulatedBalance);

  // This is the current profit and loss of the balance at the snapshot using
  // the oracle price of the token balance in the underlying token precision.
  // (_accumulatedBalance * oraclePrice) - _accumulatedCostRealized
  snapshot.currentProfitAndLossAtSnapshot = snapshot._accumulatedBalance
    .times(underlyingToken.precision)
    .times(spotPrice)
    .div(DEFAULT_PRECISION)
    .div(token.precision)
    .minus(snapshot._accumulatedCostRealized);

  if (token.tokenType == VAULT_DEBT) {
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
}
