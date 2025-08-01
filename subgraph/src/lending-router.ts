import { Address, BigInt, ByteArray, Bytes, crypto, ethereum } from "@graphprotocol/graph-ts";
import {
  EnterPosition,
  ExitPosition,
  ILendingRouter,
  LiquidatePosition,
} from "../generated/templates/LendingRouter/ILendingRouter";
import { createERC20TokenAsset, getBorrowShare, getToken } from "./entities/token";
import { IYieldStrategy } from "../generated/templates/LendingRouter/IYieldStrategy";
import { createSnapshotForIncentives, createTradeExecutionLineItem, setProfitLossLineItem } from "./entities/balance";
import { loadAccount } from "./entities/account";
import { Account, Token } from "../generated/schema";
import { DEFAULT_PRECISION, ZERO_ADDRESS } from "./constants";

function getBorrowSharePrice(
  borrowAssets: BigInt,
  borrowShares: BigInt,
  underlyingToken: Token,
  borrowShare: Token,
): BigInt {
  return borrowAssets
    .times(DEFAULT_PRECISION)
    .times(borrowShare.precision)
    .div(borrowShares)
    .div(underlyingToken.precision);
}

export function convertPrice(price: BigInt, underlyingToken: Token): BigInt {
  return price.times(underlyingToken.precision).div(DEFAULT_PRECISION);
}

export function handleEnterPosition(event: EnterPosition): void {
  let l = ILendingRouter.bind(event.address);
  let v = IYieldStrategy.bind(event.params.vault);
  let underlyingToken = getToken(v.asset().toHexString());
  let account = loadAccount(event.params.user.toHexString(), event);

  let borrowAssets = BigInt.zero();
  if (event.params.borrowShares.gt(BigInt.zero())) {
    let borrowShare = getBorrowShare(event.params.vault, event.address, event);
    borrowAssets = l.convertBorrowSharesToAssets(event.params.vault, event.params.borrowShares);
    let borrowSharePrice = getBorrowSharePrice(borrowAssets, event.params.borrowShares, underlyingToken, borrowShare);

    setProfitLossLineItem(
      account,
      borrowShare,
      underlyingToken,
      event.params.borrowShares,
      borrowAssets,
      borrowSharePrice,
      event.params.wasMigrated ? "MigratePosition" : "EnterPosition",
      event.address,
      event,
    );
  }

  if (event.params.vaultSharesReceived.gt(BigInt.zero())) {
    let vaultShare = getToken(event.params.vault.toHexString());
    // This comes in as 1e36 so divide it by 1e18 to get the price in the correct precision
    let oraclePrice = convertPrice(v.price1(event.params.user), underlyingToken);
    let underlyingAmountRealized = borrowAssets.plus(event.params.depositAssets);

    setProfitLossLineItem(
      account,
      vaultShare,
      underlyingToken,
      event.params.vaultSharesReceived,
      underlyingAmountRealized,
      oraclePrice,
      event.params.wasMigrated ? "MigratePosition" : "EnterPosition",
      event.address,
      event,
    );
  }

  parseVaultEvents(account, event.params.vault, event);
}

export function handleExitPosition(event: ExitPosition): void {
  let l = ILendingRouter.bind(event.address);
  let v = IYieldStrategy.bind(event.params.vault);
  let underlyingToken = getToken(v.asset().toHexString());
  let account = loadAccount(event.params.user.toHexString(), event);
  let borrowShare = getBorrowShare(event.params.vault, event.address, event);
  let borrowAssetsRepaid = l.convertBorrowSharesToAssets(event.params.vault, event.params.borrowSharesRepaid);
  let borrowSharePrice = getBorrowSharePrice(
    borrowAssetsRepaid,
    event.params.borrowSharesRepaid,
    underlyingToken,
    borrowShare,
  );

  if (event.params.borrowSharesRepaid.gt(BigInt.zero())) {
    setProfitLossLineItem(
      account,
      borrowShare,
      underlyingToken,
      // Negative because we are burning borrow shares
      event.params.borrowSharesRepaid.neg(),
      borrowAssetsRepaid.neg(),
      borrowSharePrice,
      "ExitPosition",
      event.address,
      event,
    );
  }

  if (event.params.vaultSharesBurned.gt(BigInt.zero())) {
    let vaultShare = getToken(event.params.vault.toHexString());
    let oraclePrice = convertPrice(v.price1(event.params.user), underlyingToken);

    setProfitLossLineItem(
      account,
      vaultShare,
      underlyingToken,
      // Negative because we are burning vault shares
      event.params.vaultSharesBurned.neg(),
      event.params.profitsWithdrawn.plus(borrowAssetsRepaid).neg(),
      oraclePrice,
      "ExitPosition",
      event.address,
      event,
    );
  }

  parseVaultEvents(account, event.params.vault, event);
}

export function handleLiquidatePosition(event: LiquidatePosition): void {
  let l = ILendingRouter.bind(event.address);
  let v = IYieldStrategy.bind(event.params.vault);
  let underlyingToken = getToken(v.asset().toHexString());
  let vaultShare = getToken(event.params.vault.toHexString());
  let account = loadAccount(event.params.user.toHexString(), event);
  let liquidator = loadAccount(event.params.liquidator.toHexString(), event);
  let borrowShare = getBorrowShare(event.params.vault, event.address, event);

  let borrowAssetsRepaid = l.convertBorrowSharesToAssets(event.params.vault, event.params.borrowSharesRepaid);
  let borrowSharePrice = getBorrowSharePrice(
    borrowAssetsRepaid,
    event.params.borrowSharesRepaid,
    underlyingToken,
    borrowShare,
  );
  let vaultSharePrice = convertPrice(v.price1(event.params.user), underlyingToken);

  // Remove the borrow share from the account
  setProfitLossLineItem(
    account,
    borrowShare,
    underlyingToken,
    event.params.borrowSharesRepaid.neg(),
    borrowAssetsRepaid.neg(),
    borrowSharePrice,
    "LiquidatePosition",
    event.address,
    event,
  );

  // Remove the vault shares from the account
  setProfitLossLineItem(
    account,
    vaultShare,
    underlyingToken,
    event.params.vaultSharesToLiquidator.neg(),
    borrowAssetsRepaid.neg(),
    vaultSharePrice,
    "LiquidatePosition",
    event.address,
    event,
  );

  // Add the vault shares to the liquidator
  setProfitLossLineItem(
    liquidator,
    vaultShare,
    underlyingToken,
    event.params.vaultSharesToLiquidator,
    borrowAssetsRepaid,
    vaultSharePrice,
    "LiquidatePosition",
    ZERO_ADDRESS, // The liquidator holds the position natively
    event,
  );

  parseVaultEvents(account, event.params.vault, event);
}

function parseVaultEvents(account: Account, vaultAddress: Address, event: ethereum.Event): void {
  if (event.receipt === null) return;

  for (let i = 0; i < event.receipt!.logs.length; i++) {
    let _log = event.receipt!.logs[i];
    if (_log.address.toHexString() != vaultAddress.toHexString()) continue;

    if (_log.topics[0] == crypto.keccak256(ByteArray.fromUTF8("VaultRewardTransfer(address,address,uint256)"))) {
      // We do this here because we don't know the current lending router in order
      // to get the proper balance snapshot so these need to be done after the balance
      // snapshots are updated.
      let rewardToken = Address.fromBytes(changetype<Bytes>(_log.topics[1].slice(12)));
      let account = Address.fromBytes(changetype<Bytes>(_log.topics[2].slice(12)));
      let amount = BigInt.fromUnsignedBytes(changetype<ByteArray>(_log.data.reverse()));
      createSnapshotForIncentives(loadAccount(account.toHexString(), event), vaultAddress, rewardToken, amount, event);
    } else if (
      _log.topics[0] == crypto.keccak256(ByteArray.fromUTF8("TradeExecuted(address,address,uint256,uint256)"))
    ) {
      // NOTE: the account is the one doing the trade here.
      let sellToken = Address.fromBytes(changetype<Bytes>(_log.topics[1].slice(12)));
      let buyToken = Address.fromBytes(changetype<Bytes>(_log.topics[2].slice(12)));
      let sellAmount = BigInt.fromUnsignedBytes(changetype<ByteArray>(_log.data.slice(0, 32).reverse()));
      let buyAmount = BigInt.fromUnsignedBytes(changetype<ByteArray>(_log.data.slice(32).reverse()));

      createTradeExecutionLineItem(
        account,
        vaultAddress,
        createERC20TokenAsset(sellToken, event, "VaultShare"),
        createERC20TokenAsset(buyToken, event, "VaultShare"),
        sellAmount,
        buyAmount,
        BigInt.fromI32(i),
        event,
      );
    }
  }
}
