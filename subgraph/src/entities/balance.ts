import { ethereum, BigInt, log, Address, ByteArray, crypto, Bytes } from "@graphprotocol/graph-ts";
import {
  Account,
  Balance,
  BalanceSnapshot,
  IncentiveSnapshot,
  ProfitLossLineItem,
  Token,
} from "../../generated/schema";
import {
  ADDRESS_REGISTRY,
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
import { getToken } from "./token";
import { AddressRegistry } from "../../generated/AddressRegistry/AddressRegistry";
import { IWithdrawRequestManager } from "../../generated/AddressRegistry/IWithdrawRequestManager";

function getVaultShareBalance(balance: Balance): BigInt {
  if (balance.lendingRouter === null) {
    // Get the balance using the native balance on the vault
    let v = IERC20Metadata.bind(Address.fromBytes(Address.fromHexString(balance.token)));
    return v.balanceOf(Address.fromBytes(Address.fromHexString(balance.account)));
  } else {
    let l = ILendingRouter.bind(Address.fromBytes(Address.fromHexString(balance.lendingRouter as string)));
    return l.balanceOfCollateral(
      Address.fromBytes(Address.fromHexString(balance.account)),
      Address.fromBytes(Address.fromHexString(balance.token)),
    );
  }
}

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
  let incentiveSnapshotId = balance.id + ":" + event.block.number.toString() + ":" + rewardToken.toHexString();

  let incentiveSnapshot = new IncentiveSnapshot(incentiveSnapshotId);
  incentiveSnapshot.blockNumber = event.block.number;
  incentiveSnapshot.timestamp = event.block.timestamp.toI32();
  incentiveSnapshot.transactionHash = event.transaction.hash;
  incentiveSnapshot.balance = balance.id;
  incentiveSnapshot.rewardToken = rewardToken.toHexString();
  incentiveSnapshot.account = account.id;
  incentiveSnapshot.amountClaimed = amount;

  incentiveSnapshot.totalClaimed = BigInt.zero();
  incentiveSnapshot.adjustedClaimed = BigInt.zero();

  if (balance._lastIncentiveSnapshotBlockNumber) {
    let previousIncentiveSnapshotId =
      balance.id +
      ":" +
      (balance._lastIncentiveSnapshotBlockNumber as BigInt).toString() +
      ":" +
      rewardToken.toHexString();
    let previousIncentiveSnapshot = IncentiveSnapshot.load(previousIncentiveSnapshotId);
    if (previousIncentiveSnapshot) {
      incentiveSnapshot.previousIncentiveSnapshot = previousIncentiveSnapshotId;
      incentiveSnapshot.totalClaimed = previousIncentiveSnapshot.totalClaimed;
      incentiveSnapshot.adjustedClaimed = previousIncentiveSnapshot.adjustedClaimed;
    }
  }

  incentiveSnapshot.totalClaimed = incentiveSnapshot.totalClaimed.plus(amount);
  incentiveSnapshot.adjustedClaimed = incentiveSnapshot.adjustedClaimed.plus(amount);

  let snapshot = BalanceSnapshot.load(balance.current);
  let currentBalance = BigInt.zero();
  let previousBalance = BigInt.zero();
  if (snapshot === null) return;
  if (snapshot.blockNumber.equals(event.block.number)) {
    // In this case the snapshot is up to date.
    currentBalance = snapshot.currentBalance;
    previousBalance = snapshot.previousBalance;
  } else {
    // In this case the snapshot is not up to date and we fetch the latest balance
    currentBalance = getVaultShareBalance(balance);
    previousBalance = snapshot.currentBalance;
  }

  if (currentBalance.lt(previousBalance)) {
    // On vault share decrease apply this adjustment after the above line
    // adjustedClaimed = adjustedClaimed - (prevBalance - currentBalance) * adjustedClaimed / prevBalance
    incentiveSnapshot.adjustedClaimed = incentiveSnapshot.adjustedClaimed.minus(
      previousBalance.minus(currentBalance).times(incentiveSnapshot.adjustedClaimed).div(previousBalance),
    );
  }

  balance._lastIncentiveSnapshotBlockNumber = event.block.number;
  balance.save();
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
  lineItem.token = buyToken.id;
  lineItem.account = account.id;
  lineItem.underlyingToken = sellToken.id;

  lineItem.tokenAmount = buyAmount;
  lineItem.underlyingAmountRealized = sellAmount;
  // Spot prices are not known on chain for trades
  lineItem.underlyingAmountSpot = BigInt.zero();
  lineItem.spotPrice = BigInt.zero();

  if (sellAmount.gt(BigInt.zero())) {
    // NOTE: this is in underlying token precision (sellToken)
    lineItem.realizedPrice = sellAmount.times(buyToken.precision).div(buyAmount);
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

export function createWithdrawRequestLineItem(
  account: Account,
  vaultAddress: Address,
  vaultShares: BigInt,
  yieldTokenAmount: BigInt,
  balanceSnapshotId: string,
  event: ethereum.Event,
): void {
  let id =
    event.transaction.hash.toHex() +
    ":" +
    event.logIndex.toString() +
    ":" +
    account.id +
    ":" +
    vaultAddress.toHexString();
  let v = IYieldStrategy.bind(Address.fromBytes(vaultAddress));
  let y = getToken(v.yieldToken().toHexString());
  let vToken = getToken(vaultAddress.toHexString());

  let lineItem = new ProfitLossLineItem(id);
  lineItem.blockNumber = event.block.number;
  lineItem.timestamp = event.block.timestamp.toI32();
  lineItem.transactionHash = event.transaction.hash;
  lineItem.token = vaultAddress.toHexString();
  lineItem.account = account.id;
  lineItem.underlyingToken = y.id;

  lineItem.tokenAmount = vaultShares;
  lineItem.underlyingAmountRealized = yieldTokenAmount;
  lineItem.spotPrice = v.convertSharesToYieldToken(DEFAULT_PRECISION);
  lineItem.underlyingAmountSpot = v.convertSharesToYieldToken(vaultShares.abs());

  if (yieldTokenAmount.lt(BigInt.zero())) {
    lineItem.underlyingAmountSpot = lineItem.underlyingAmountSpot.neg();
  }

  // This is in underlying token precision (yieldToken)
  lineItem.realizedPrice = yieldTokenAmount.times(vToken.precision).div(vaultShares);

  lineItem.lineItemType = "WithdrawRequest";
  lineItem.balanceSnapshot = balanceSnapshotId;

  lineItem.save();
}

export function createWithdrawRequestFinalizedLineItem(
  account: Account,
  vaultAddress: Address,
  yieldTokenAmount: BigInt,
  withdrawTokenAmount: BigInt,
  withdrawToken: Token,
  balanceSnapshotId: string,
  event: ethereum.Event,
): void {
  let id =
    event.transaction.hash.toHex() +
    ":" +
    event.logIndex.toString() +
    ":" +
    account.id +
    ":" +
    vaultAddress.toHexString();

  let v = IYieldStrategy.bind(Address.fromBytes(vaultAddress));
  let y = getToken(v.yieldToken().toHexString());

  let lineItem = new ProfitLossLineItem(id);
  lineItem.blockNumber = event.block.number;
  lineItem.timestamp = event.block.timestamp.toI32();
  lineItem.transactionHash = event.transaction.hash;
  lineItem.token = y.id;
  lineItem.account = account.id;
  lineItem.underlyingToken = withdrawToken.id;

  lineItem.tokenAmount = yieldTokenAmount;
  lineItem.underlyingAmountRealized = withdrawTokenAmount;

  // This is in underlying token precision (withdrawToken)
  lineItem.realizedPrice = withdrawTokenAmount.times(y.precision).div(yieldTokenAmount);
  lineItem.spotPrice = BigInt.zero();
  lineItem.underlyingAmountSpot = BigInt.zero();

  lineItem.lineItemType = "WithdrawRequestFinalized";
  lineItem.balanceSnapshot = balanceSnapshotId;

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

  if (token.tokenType == VAULT_SHARE) {
    // Sets the yield token amount if the token is a vault share
    let vault = IYieldStrategy.bind(Address.fromBytes(Address.fromHexString(token.vaultAddress!)));
    let result = vault.try_convertSharesToYieldToken(tokenAmount.abs());
    if (!result.reverted) {
      lineItem.yieldTokenAmount = result.value;
    }
  }

  if (tokenAmount.notEqual(BigInt.zero())) {
    // This is reported in underlying token precision
    lineItem.realizedPrice = underlyingAmountRealized.times(token.precision).div(tokenAmount);
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

  if (lendingRouter == ZERO_ADDRESS) {
    balance.lendingRouter = null;
  } else {
    balance.lendingRouter = lendingRouter.toHexString();
  }

  if (token.tokenType == VAULT_SHARE && token.vaultAddress !== null) {
    snapshot.currentBalance = getVaultShareBalance(balance);
  } else if (token.tokenType == VAULT_DEBT && token.vaultAddress !== null) {
    if (lendingRouter == ZERO_ADDRESS) {
      snapshot.currentBalance = BigInt.zero();
    } else {
      let l = ILendingRouter.bind(lendingRouter);
      snapshot.currentBalance = l.balanceOfBorrowShares(
        accountAddress,
        Address.fromBytes(Address.fromHexString(token.vaultAddress!)),
      );
    }
  }

  balance.save();
  snapshot.save();

  return snapshot;
}

function findPendleTokenInAmount(
  vaultAddress: Address,
  tokenInSy: Address,
  event: ethereum.Event,
  isEntry: boolean,
): BigInt {
  if (event.receipt === null) return BigInt.zero();

  for (let i = 0; i < event.receipt!.logs.length; i++) {
    let _log = event.receipt!.logs[i];
    if (_log.address.toHexString() != vaultAddress.toHexString()) continue;

    if (_log.topics[0] == crypto.keccak256(ByteArray.fromUTF8("TradeExecuted(address,address,uint256,uint256)"))) {
      let sellToken = Address.fromBytes(changetype<Bytes>(_log.topics[1].slice(12)));
      let buyToken = Address.fromBytes(changetype<Bytes>(_log.topics[2].slice(12)));
      let sellAmount = BigInt.fromUnsignedBytes(changetype<ByteArray>(_log.data.slice(0, 32).reverse()));
      let buyAmount = BigInt.fromUnsignedBytes(changetype<ByteArray>(_log.data.slice(32).reverse()));

      // Only look for the tokenInSy on the sell side if it is an entry, buyToken on exit
      if (sellToken == tokenInSy && isEntry) {
        return sellAmount;
      } else if (buyToken == tokenInSy && !isEntry) {
        return buyAmount;
      }
    }
  }

  return BigInt.zero();
}

function getInterestAccumulator(v: IYieldStrategy, strategy: string): BigInt {
  let yieldToken = v.yieldToken();
  let accountingAsset = v.accountingAsset();
  let t = ITradingModule.bind(Address.fromBytes(TRADING_MODULE));

  if (strategy == "Staking") {
    let r = AddressRegistry.bind(changetype<Address>(ADDRESS_REGISTRY));
    let wrm = r.getWithdrawRequestManager(yieldToken);
    if (wrm != Address.zero()) {
      let w = IWithdrawRequestManager.bind(wrm);
      let r = w.try_getExchangeRate();
      if (!r.reverted) {
        return r.value;
      }
    }

    return t.getOraclePrice(yieldToken, accountingAsset).getAnswer();
  } else {
    // NOTE: this can go negative if the price goes down.
    return v.convertToAssets(DEFAULT_PRECISION);
  }
}

export function getPendleInterestAccrued(
  v: IYieldStrategy,
  tokenAmount: BigInt,
  lastInterestAccumulator: BigInt,
  lastSnapshotTimestamp: BigInt,
  event: ethereum.Event,
): BigInt[] {
  let yieldToken = v.yieldToken();
  let accountingAsset = v.accountingAsset();

  let pt = IPPrincipalToken.bind(Address.fromBytes(yieldToken));
  let expiry = pt.expiry();
  let timeToExpiry = expiry.minus(event.block.timestamp);
  let ptTokens = v.convertSharesToYieldToken(tokenAmount);
  let y = getToken(yieldToken.toHexString());
  let asset = getToken(accountingAsset.toHexString());

  let x: f64 =
    (v.feeRate().times(RATE_PRECISION).times(timeToExpiry).div(DEFAULT_PRECISION).toI64() as f64) /
    (SECONDS_IN_YEAR.times(RATE_PRECISION).toI64() as f64);

  let discountFactor = BigInt.fromI64(Math.floor(Math.exp(x) * (RATE_PRECISION.toI64() as f64)) as i64);
  let marginalPtAtMaturity = ptTokens.times(RATE_PRECISION).div(discountFactor);
  // On entry look for the sellToken and on exit look for the buyToken that equals the accounting asset
  let tokenInAmount = findPendleTokenInAmount(v._address, accountingAsset, event, tokenAmount.gt(BigInt.zero()));
  let tokenInAmountScaled = tokenInAmount.times(y.precision).div(asset.precision);
  // This is the new value of the accumulator
  let newInterestAccumulator = marginalPtAtMaturity.minus(tokenInAmountScaled);

  let timeSinceLastSnapshot = event.block.timestamp.minus(lastSnapshotTimestamp);
  let timeToExpiryBefore = expiry.minus(lastSnapshotTimestamp);
  // Use the minimum of the time since the last snapshot and the time to expiry
  let interestAccrueTime = timeSinceLastSnapshot.lt(timeToExpiryBefore) ? timeSinceLastSnapshot : timeToExpiryBefore;
  let interestAccrued = lastInterestAccumulator.times(interestAccrueTime).div(timeToExpiryBefore);
  // Adjust the new interest accumulator based on the interest accrued since the last snapshot
  newInterestAccumulator = newInterestAccumulator.plus(lastInterestAccumulator).minus(interestAccrued);
  return [interestAccrued, newInterestAccumulator];
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
    let v = IYieldStrategy.bind(Address.fromBytes(Address.fromHexString(token.vaultAddress!)));
    let y = getToken(v.yieldToken().toHexString());
    let strategy = v.strategy();

    let interestAccumulator: BigInt;
    let vaultFeeAccumulator: BigInt;
    let interestAccruedSinceLastSnapshot: BigInt;
    let vaultFeesAccruedSinceLastSnapshot: BigInt;
    if (balance.withdrawRequest === null) {
      if (strategy == "PendlePT") {
        let r = getPendleInterestAccrued(
          v,
          tokenAmount,
          snapshot._lastInterestAccumulator,
          BigInt.fromI32(snapshot.timestamp),
          event,
        );
        interestAccruedSinceLastSnapshot = r[0];
        interestAccumulator = r[1];
      } else {
        interestAccumulator = getInterestAccumulator(v, strategy);
        // This accumulator is in the underlying basis.
        interestAccruedSinceLastSnapshot = interestAccumulator
          .minus(snapshot._lastInterestAccumulator)
          .times(snapshot._accumulatedBalance)
          .div(token.precision);
      }

      // This is the number of yield tokens per vault share, it is decreasing over time. Convert this
      // to default precision
      vaultFeeAccumulator = v.convertSharesToYieldToken(DEFAULT_PRECISION).times(DEFAULT_PRECISION).div(y.precision);
      // This accumulator is in a yield token basis.
      vaultFeesAccruedSinceLastSnapshot = snapshot._lastVaultFeeAccumulator
        .minus(vaultFeeAccumulator)
        .times(snapshot._accumulatedBalance)
        .div(DEFAULT_PRECISION);
    } else {
      // Pause the interest accrual and vault fees accrual during a withdraw request
      interestAccumulator = snapshot._lastInterestAccumulator;
      interestAccruedSinceLastSnapshot = BigInt.zero();
      vaultFeeAccumulator = snapshot._lastVaultFeeAccumulator;
      vaultFeesAccruedSinceLastSnapshot = BigInt.zero();
    }

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
  if (tokenAmount.lt(BigInt.zero()) && snapshot.previousBalance.gt(BigInt.zero())) {
    // Scale down the cost basis when the token amount decreases
    snapshot._accumulatedCostRealized = snapshot._accumulatedCostRealized
      .times(snapshot.currentBalance)
      .div(snapshot.previousBalance);
  } else {
    snapshot._accumulatedCostRealized = snapshot._accumulatedCostRealized.plus(underlyingAmountRealized);
  }

  // This is the average cost basis of the balance in the underlying token precision
  if (snapshot._accumulatedBalance.gt(BigInt.zero())) {
    snapshot.adjustedCostBasis = snapshot._accumulatedCostRealized
      .times(token.precision)
      .div(snapshot._accumulatedBalance);
  } else {
    snapshot.adjustedCostBasis = BigInt.zero();
  }

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
