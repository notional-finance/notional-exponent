import { BigInt } from "@graphprotocol/graph-ts";
import { EnterPosition, ExitPosition, ILendingRouter, LiquidatePosition } from "../generated/templates/LendingRouter/ILendingRouter";
import { getBorrowShare, getToken } from "./entities/token";
import { IYieldStrategy } from "../generated/templates/LendingRouter/IYieldStrategy";
import { setProfitLossLineItem } from "./entities/balance";
import { loadAccount } from "./entities/account";

export function handleEnterPosition(event: EnterPosition): void {
  let l = ILendingRouter.bind(event.address);
  let v = IYieldStrategy.bind(event.params.vault);
  let underlyingToken = getToken(v.asset().toHexString());
  let account = loadAccount(event.params.user.toHexString(), event);

  if (event.params.vaultSharesReceived.gt(BigInt.zero())) {
    let vaultShare = getToken(event.params.vault.toHexString());
    let oraclePrice = v.price1(event.params.user);

    setProfitLossLineItem(
      account,
      vaultShare,
      underlyingToken,
      event.params.vaultSharesReceived,
      event.params.borrowShares,
      oraclePrice,
      event.params.wasMigrated ? "MigratePosition" : "EnterPosition",
      event
    );
  }

  if (event.params.borrowShares.gt(BigInt.zero())) {
    let borrowShare = getBorrowShare(event.params.vault, event.address, event);
    let borrowSharePrice = BigInt.zero();
    let borrowAsset = event.params.borrowShares.times(borrowSharePrice).div(borrowShare.precision);

    setProfitLossLineItem(
      account,
      borrowShare,
      underlyingToken,
      event.params.borrowShares,
      borrowAsset,
      borrowSharePrice,
      event.params.wasMigrated ? "MigratePosition" : "EnterPosition",
      event
    );
  }
}

export function handleExitPosition(event: ExitPosition): void {
  let l = ILendingRouter.bind(event.address);
  let v = IYieldStrategy.bind(event.params.vault);
  let underlyingToken = getToken(v.asset().toHexString());
  let account = loadAccount(event.params.user.toHexString(), event);
  let borrowAssetsRepaid = BigInt.zero();

  if (event.params.borrowSharesRepaid.gt(BigInt.zero())) {
    let borrowShare = getBorrowShare(event.params.vault, event.address, event);
    let borrowSharePrice = BigInt.zero();
    borrowAssetsRepaid = event.params.borrowSharesRepaid.times(borrowSharePrice).div(borrowShare.precision);

    setProfitLossLineItem(
      account,
      borrowShare,
      underlyingToken,
      // Negative because we are burning borrow shares
      event.params.borrowSharesRepaid.neg(),
      borrowAssetsRepaid.neg(),
      borrowSharePrice,
      "ExitPosition",
      event
    );
  }

  if (event.params.vaultSharesBurned.gt(BigInt.zero())) {
    let vaultShare = getToken(event.params.vault.toHexString());
    let oraclePrice = v.price1(event.params.user);

    setProfitLossLineItem(
      account,
      vaultShare,
      underlyingToken,
      // Negative because we are burning vault shares
      event.params.vaultSharesBurned.neg(),
      event.params.profitsWithdrawn.plus(borrowAssetsRepaid).neg(),
      oraclePrice,
      "ExitPosition",
      event
    );
  }
}

export function handleLiquidatePosition(event: LiquidatePosition): void {
  let l = ILendingRouter.bind(event.address);
  let v = IYieldStrategy.bind(event.params.vault);
  let underlyingToken = getToken(v.asset().toHexString());
  let vaultShare = getToken(event.params.vault.toHexString());
  let account = loadAccount(event.params.user.toHexString(), event);
  let borrowShare = getBorrowShare(event.params.vault, event.address, event);
  let borrowSharePrice = BigInt.zero();
  let vaultSharePrice = BigInt.zero();
  let borrowAssetsRepaid = event.params.borrowSharesRepaid.times(borrowSharePrice).div(borrowShare.precision);

  // Remove the borrow share from the account
  setProfitLossLineItem(
    account,
    borrowShare,
    underlyingToken,
    event.params.borrowSharesRepaid.neg(),
    borrowAssetsRepaid.neg(),
    borrowSharePrice,
    "LiquidatePosition",
    event
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
    event
  );

  // Add the vault shares to the liquidator
  setProfitLossLineItem(
    account,
    vaultShare,
    underlyingToken,
    event.params.vaultSharesToLiquidator,
    borrowAssetsRepaid,
    vaultSharePrice,
    "LiquidatePosition",
    event
  );

}