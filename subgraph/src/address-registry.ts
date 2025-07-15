import {
  LendingRouterSet,
  WhitelistedVault,
  WithdrawRequestManagerSet
} from "../generated/AddressRegistry/AddressRegistry"
import { IYieldStrategy } from "../generated/AddressRegistry/IYieldStrategy"
import { IWithdrawRequestManager } from "../generated/AddressRegistry/IWithdrawRequestManager"
import { LendingRouter, Oracle, Vault, WithdrawRequestManager } from "../generated/schema"
import { createERC20TokenAsset } from "./entities/token"
import { UNDERLYING, VAULT_SHARE } from "./constants"
import { 
  Vault as VaultTemplate,
  WithdrawRequestManager as WithdrawRequestManagerTemplate,
  LendingRouter as LendingRouterTemplate
} from "../generated/templates"
import { getOracleRegistry, updateChainlinkOracle, updateVaultOracles } from "./entities/oracles"
import { Address, ethereum } from "@graphprotocol/graph-ts"

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
  lendingRouter.save();

  LendingRouterTemplate.create(event.params.lendingRouter);

  let r = getOracleRegistry()
  let l = r.lendingRouters
  l.push(event.params.lendingRouter);
  r.lendingRouters = l;
  r.save();
}

export function handleWhitelistedVault(event: WhitelistedVault): void {
  const id = event.params.vault.toHexString();
  let vault = Vault.load(id);
  if (!vault) {
    vault = new Vault(id);
    vault.firstUpdateBlockNumber = event.block.number;
    vault.firstUpdateTimestamp = event.block.timestamp.toI32();
    vault.firstUpdateTransactionHash = event.transaction.hash;
  }

  vault.isWhitelisted = event.params.isWhitelisted;
  vault.lastUpdateBlockNumber = event.block.number;
  vault.lastUpdateTimestamp = event.block.timestamp.toI32();
  vault.lastUpdateTransactionHash = event.transaction.hash;

  let yieldStrategy = IYieldStrategy.bind(event.params.vault);
  vault.feeRate = yieldStrategy.feeRate();
  vault.yieldToken = createERC20TokenAsset(yieldStrategy.yieldToken(), event, UNDERLYING).id;
  vault.asset = createERC20TokenAsset(yieldStrategy.asset(), event, UNDERLYING).id;

  let vaultToken = createERC20TokenAsset(event.params.vault, event, VAULT_SHARE);
  vault.vaultToken = vaultToken.id;
  vaultToken.vaultAddress = event.params.vault;
  vaultToken.underlying = vault.asset;
  vaultToken.save();

  // These will be listed on approval
  vault.withdrawRequestManagers = [];

  vault.save();

  VaultTemplate.create(event.params.vault);

  let r = getOracleRegistry()
  let l = r.listedVaults
  l.push(event.params.vault);
  r.listedVaults = l;
  r.save();
}

export function handleWithdrawRequestManagerSet(
  event: WithdrawRequestManagerSet
): void {
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

  let r = getOracleRegistry()
  let wrm = r.withdrawRequestManager
  wrm.push(event.params.withdrawRequestManager);
  r.withdrawRequestManager = wrm;
  r.save();
}

export function handleBlockOracleUpdate(block: ethereum.Block): void {
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

  // for (let i = 0; i < registry.withdrawRequestManager.length; i++) {
  //   updateWithdrawRequestManagerOracles(Address.fromBytes(registry.withdrawRequestManager[i]), block);
  // }
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
