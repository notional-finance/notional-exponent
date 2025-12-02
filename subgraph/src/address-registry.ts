import {
  LendingRouterSet,
  WhitelistedVault,
  WithdrawRequestManagerSet,
} from "../generated/AddressRegistry/AddressRegistry";
import { IYieldStrategy } from "../generated/AddressRegistry/IYieldStrategy";
import { IWithdrawRequestManager } from "../generated/AddressRegistry/IWithdrawRequestManager";
import { LendingRouter, Oracle, OracleRegistry, Vault, WithdrawRequestManager } from "../generated/schema";
import { createERC20TokenAsset, getBorrowShare, getToken } from "./entities/token";
import { ORACLE_REGISTRY_ID, UNDERLYING, VAULT_SHARE } from "./constants";
import {
  Vault as VaultTemplate,
  WithdrawRequestManager as WithdrawRequestManagerTemplate,
  LendingRouter as LendingRouterTemplate,
} from "../generated/templates";
import {
  getOracle,
  getOracleRegistry,
  updateChainlinkOracle,
  updateExchangeRate,
  updateVaultOracles,
  updateWithdrawRequestManagerOracles,
} from "./entities/oracles";
import { Address, ethereum } from "@graphprotocol/graph-ts";
import { ILendingRouter } from "../generated/AddressRegistry/ILendingRouter";
import { handleInitialOracles } from "./trading-module";
import { getMarketParams } from "./entities/market";

export function handleLendingRouterSet(event: LendingRouterSet): void {
  const id = event.params.lendingRouter.toHexString();
  let lendingRouter = LendingRouter.load(id);
  if (!lendingRouter) {
    lendingRouter = new LendingRouter(id);
    lendingRouter.firstUpdateBlockNumber = event.block.number;
    lendingRouter.firstUpdateTimestamp = event.block.timestamp.toI32();
    lendingRouter.firstUpdateTransactionHash = event.transaction.hash;
  }

  lendingRouter.lastUpdateBlockNumber = event.block.number;
  lendingRouter.lastUpdateTimestamp = event.block.timestamp.toI32();
  lendingRouter.lastUpdateTransactionHash = event.transaction.hash;
  let lr = ILendingRouter.bind(event.params.lendingRouter);
  lendingRouter.name = lr.name();
  lendingRouter.save();

  LendingRouterTemplate.create(event.params.lendingRouter);

  let r = getOracleRegistry();
  let l = r.lendingRouters;
  l.push(event.params.lendingRouter);
  r.lendingRouters = l;
  r.save();
}

export function createVault(address: Address, event: ethereum.Event, isWhitelisted: boolean): Vault {
  const id = address.toHexString();
  let vault = Vault.load(id);
  if (vault) return vault;

  vault = new Vault(id);
  vault.firstUpdateBlockNumber = event.block.number;
  vault.firstUpdateTimestamp = event.block.timestamp.toI32();
  vault.firstUpdateTransactionHash = event.transaction.hash;

  vault.isWhitelisted = isWhitelisted;
  vault.lastUpdateBlockNumber = event.block.number;
  vault.lastUpdateTimestamp = event.block.timestamp.toI32();
  vault.lastUpdateTransactionHash = event.transaction.hash;

  let yieldStrategy = IYieldStrategy.bind(address);
  vault.feeRate = yieldStrategy.feeRate();
  vault.yieldToken = createERC20TokenAsset(yieldStrategy.yieldToken(), event, UNDERLYING).id;
  vault.asset = createERC20TokenAsset(yieldStrategy.asset(), event, UNDERLYING).id;
  vault.strategyType = yieldStrategy.strategy();
  vault.accountingAsset = createERC20TokenAsset(yieldStrategy.accountingAsset(), event, UNDERLYING).id;

  let vaultToken = createERC20TokenAsset(address, event, VAULT_SHARE);
  vault.vaultToken = vaultToken.id;
  vaultToken.vaultAddress = address.toHexString();
  vaultToken.underlying = vault.asset;
  vaultToken.save();

  // These will be listed on approval
  vault.withdrawRequestManagers = [];
  vault.save();

  return vault;
}

export function handleWhitelistedVault(event: WhitelistedVault): void {
  let vault = createVault(event.params.vault, event, event.params.isWhitelisted);
  vault.isWhitelisted = event.params.isWhitelisted;
  vault.save();

  VaultTemplate.create(event.params.vault);

  let r = getOracleRegistry();
  let l = r.listedVaults;
  l.push(event.params.vault);
  r.listedVaults = l;
  r.save();

  for (let i = 0; i < r.lendingRouters.length; i++) {
    // Create the initial borrow share entity for the vault / lending router combination.
    let v = IYieldStrategy.bind(event.params.vault);
    let borrowShare = getBorrowShare(event.params.vault, Address.fromBytes(r.lendingRouters[i]), event);
    getMarketParams(Address.fromBytes(r.lendingRouters[i]), event.params.vault, event);

    // Create the initial borrow share oracle for the vault / lending router combination. The price
    // is set to 1-1 with the asset.
    let asset = getToken(v.asset().toHexString());
    let borrowShareOracle = getOracle(asset, borrowShare, "BorrowShareOracleRate");
    borrowShareOracle.decimals = asset.decimals;
    borrowShareOracle.ratePrecision = asset.precision;
    borrowShareOracle.oracleAddress = Address.fromBytes(r.lendingRouters[i]);
    updateExchangeRate(borrowShareOracle, asset.precision, event.block);
  }
}

export function handleWithdrawRequestManagerSet(event: WithdrawRequestManagerSet): void {
  const id = event.params.withdrawRequestManager.toHexString();
  let withdrawRequestManager = WithdrawRequestManager.load(id);
  if (!withdrawRequestManager) {
    withdrawRequestManager = new WithdrawRequestManager(id);
    withdrawRequestManager.firstUpdateBlockNumber = event.block.number;
    withdrawRequestManager.firstUpdateTimestamp = event.block.timestamp.toI32();
    withdrawRequestManager.firstUpdateTransactionHash = event.transaction.hash;
  }

  withdrawRequestManager.lastUpdateBlockNumber = event.block.number;
  withdrawRequestManager.lastUpdateTimestamp = event.block.timestamp.toI32();
  withdrawRequestManager.lastUpdateTransactionHash = event.transaction.hash;

  let w = IWithdrawRequestManager.bind(event.params.withdrawRequestManager);
  withdrawRequestManager.yieldToken = createERC20TokenAsset(w.YIELD_TOKEN(), event, UNDERLYING).id;
  withdrawRequestManager.withdrawToken = createERC20TokenAsset(w.WITHDRAW_TOKEN(), event, UNDERLYING).id;
  withdrawRequestManager.stakingToken = createERC20TokenAsset(w.STAKING_TOKEN(), event, UNDERLYING).id;

  withdrawRequestManager.save();

  WithdrawRequestManagerTemplate.create(event.params.withdrawRequestManager);

  let r = getOracleRegistry();
  let wrm = r.withdrawRequestManager;
  wrm.push(event.params.withdrawRequestManager);
  r.withdrawRequestManager = wrm;
  r.save();
}

export function handleBlockOracleUpdate(block: ethereum.Block): void {
  let r = OracleRegistry.load(ORACLE_REGISTRY_ID);
  if (r === null) handleInitialOracles(block);

  let registry = getOracleRegistry();
  registry.lastRefreshBlockNumber = block.number;
  registry.lastRefreshTimestamp = block.timestamp.toI32();
  registry.save();

  // Aggregate the same oracle types with each other.
  for (let i = 0; i < registry.chainlinkOracles.length; i++) {
    let oracle = Oracle.load(registry.chainlinkOracles[i]) as Oracle;
    updateChainlinkOracle(oracle, block);
  }

  for (let i = 0; i < registry.listedVaults.length; i++) {
    updateVaultOracles(Address.fromBytes(registry.listedVaults[i]), block, registry.lendingRouters);
  }

  for (let i = 0; i < registry.withdrawRequestManager.length; i++) {
    updateWithdrawRequestManagerOracles(Address.fromBytes(registry.withdrawRequestManager[i]), block);
  }
}

// export function handleFeeReceiverTransferred(
//   event: FeeReceiverTransferred
// ): void {}

// export function handlePauseAdminTransferred(
//   event: PauseAdminTransferred
// ): void {}

// export function handlePendingPauseAdminSet(event: PendingPauseAdminSet): void {}

// export function handlePendingUpgradeAdminSet(
//   event: PendingUpgradeAdminSet
// ): void {}

// export function handleUpgradeAdminTransferred(
//   event: UpgradeAdminTransferred
// ): void {}
