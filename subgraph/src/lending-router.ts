import { Address, BigInt, ByteArray, crypto, ethereum } from "@graphprotocol/graph-ts";
import { EnterPosition, ExitPosition, ILendingRouter, LiquidatePosition } from "../generated/templates/LendingRouter/ILendingRouter";
import { createERC20TokenAsset, getBorrowShare, getToken } from "./entities/token";
import { IYieldStrategy } from "../generated/templates/LendingRouter/IYieldStrategy";
import { createSnapshotForIncentives, createTradeExecutionLineItem, setProfitLossLineItem } from "./entities/balance";
import { loadAccount } from "./entities/account";
import { Account } from "../generated/schema";

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
    // TODO: get the real value here.
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

  parseVaultEvents(account, event.params.vault, event);
}

export function handleExitPosition(event: ExitPosition): void {
  let l = ILendingRouter.bind(event.address);
  let v = IYieldStrategy.bind(event.params.vault);
  let underlyingToken = getToken(v.asset().toHexString());
  let account = loadAccount(event.params.user.toHexString(), event);
  let borrowAssetsRepaid = BigInt.zero();

  if (event.params.borrowSharesRepaid.gt(BigInt.zero())) {
    let borrowShare = getBorrowShare(event.params.vault, event.address, event);
    // TODO: get the real value here.
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
  // TODO: get the real value here.
  let borrowSharePrice = BigInt.zero();
  let vaultSharePrice = v.price1(event.params.user);
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
    liquidator,
    vaultShare,
    underlyingToken,
    event.params.vaultSharesToLiquidator,
    borrowAssetsRepaid,
    vaultSharePrice,
    "LiquidatePosition",
    event
  );

  parseVaultEvents(account, event.params.vault, event);
}


function parseVaultEvents(account: Account, vaultAddress: Address, event: ethereum.Event): void {
  if (event.receipt === null) return;

  for (let i = 0; i < event.receipt!.logs.length; i++) {
    let log = event.receipt!.logs[i];
    if (log.address.toHexString() != vaultAddress.toHexString()) continue;

    if (log.topics[0] == crypto.keccak256(ByteArray.fromUTF8("VaultRewardTransfer(address,address,uint256)"))) {
      // We do this here because we don't know the current lending router in order
      // to get the proper balance snapshot so these need to be done after the balance
      // snapshots are updated.
      let rewardToken = Address.fromBytes(log.topics[1]);
      let account = Address.fromBytes(log.topics[2]);
      let amount = BigInt.fromByteArray(log.data);
      createSnapshotForIncentives(
        loadAccount(account.toHexString(), event), vaultAddress, rewardToken, amount, event
      );
    } else if (log.topics[0] == crypto.keccak256(ByteArray.fromUTF8("TradeExecuted(address,address,uint256,uint256)"))) {
      // NOTE: the account is the one doing the trade here.
      let sellToken = Address.fromBytes(log.topics[1]);
      let buyToken = Address.fromBytes(log.topics[2]);
      let sellAmount = BigInt.fromByteArray(log.data.slice(0, 32) as ByteArray);
      let buyAmount = BigInt.fromByteArray(log.data.slice(32) as ByteArray);

      createTradeExecutionLineItem(
        account,
        vaultAddress,
        createERC20TokenAsset(sellToken, event, "VaultShare"),
        createERC20TokenAsset(buyToken, event, "VaultShare"),
        sellAmount,
        buyAmount,
        BigInt.fromI32(i),
        event
      );
    }
  }
}