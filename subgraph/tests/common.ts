import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  ApprovedVault,
  InitiateWithdrawRequest,
  WithdrawRequestTokenized,
} from "../generated/templates/WithdrawRequestManager/IWithdrawRequestManager";
import { newMockEvent } from "matchstick-as";
import { Token, Vault } from "../generated/schema";
import { handleApprovedVault } from "../src/withdraw-request-manager";

export function createInitiateWithdrawRequestEvent(
  manager: Address,
  vault: Address,
  account: Address,
  yieldTokenAmount: BigInt,
  sharesAmount: BigInt,
): InitiateWithdrawRequest {
  let initiateWithdrawRequestEvent = changetype<InitiateWithdrawRequest>(newMockEvent());

  initiateWithdrawRequestEvent.parameters = new Array();

  initiateWithdrawRequestEvent.parameters.push(new ethereum.EventParam("account", ethereum.Value.fromAddress(account)));
  initiateWithdrawRequestEvent.parameters.push(new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault)));
  initiateWithdrawRequestEvent.parameters.push(
    new ethereum.EventParam("yieldTokenAmount", ethereum.Value.fromUnsignedBigInt(yieldTokenAmount)),
  );
  initiateWithdrawRequestEvent.parameters.push(
    new ethereum.EventParam("sharesAmount", ethereum.Value.fromUnsignedBigInt(sharesAmount)),
  );
  initiateWithdrawRequestEvent.parameters.push(
    new ethereum.EventParam("requestId", ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1))),
  );

  initiateWithdrawRequestEvent.address = manager;

  return initiateWithdrawRequestEvent;
}

export function createVault(vault: Address): Vault {
  let v = new Vault(vault.toHexString());
  v.firstUpdateBlockNumber = BigInt.fromI32(1);
  v.firstUpdateTimestamp = 1;
  v.firstUpdateTransactionHash = Bytes.fromI32(1);
  v.lastUpdateBlockNumber = BigInt.fromI32(1);
  v.lastUpdateTimestamp = 1;
  v.lastUpdateTransactionHash = Bytes.fromI32(1);
  v.isWhitelisted = true;
  v.asset = "0x00000000000000000000000000000000000000ff";
  v.yieldToken = "0x00000000000000000000000000000000000000ee";
  v.vaultToken = vault.toHexString();
  v.feeRate = BigInt.fromI32(1000);
  v.withdrawRequestManagers = [];
  v.save();

  let vaultShare = new Token(vault.toHexString());
  vaultShare.firstUpdateBlockNumber = BigInt.fromI32(1);
  vaultShare.firstUpdateTimestamp = 1;
  vaultShare.firstUpdateTransactionHash = Bytes.fromI32(1);
  vaultShare.lastUpdateBlockNumber = BigInt.fromI32(1);
  vaultShare.lastUpdateTimestamp = 1;
  vaultShare.lastUpdateTransactionHash = Bytes.fromI32(1);
  vaultShare.tokenType = "VaultShare";
  vaultShare.tokenInterface = "ERC20";
  vaultShare.underlying = v.asset;
  vaultShare.name = "Vault Share";
  vaultShare.symbol = "VSH";
  vaultShare.decimals = 18;
  vaultShare.precision = BigInt.fromI32(10).pow(18);
  vaultShare.vaultAddress = vault;
  vaultShare.tokenAddress = vault;
  vaultShare.save();

  let asset = new Token(v.asset);
  asset.firstUpdateBlockNumber = BigInt.fromI32(1);
  asset.firstUpdateTimestamp = 1;
  asset.firstUpdateTransactionHash = Bytes.fromI32(1);
  asset.lastUpdateBlockNumber = BigInt.fromI32(1);
  asset.lastUpdateTimestamp = 1;
  asset.lastUpdateTransactionHash = Bytes.fromI32(1);
  asset.tokenType = "Underlying";
  asset.tokenInterface = "ERC20";
  asset.name = "Asset";
  asset.symbol = "ASSET";
  asset.decimals = 6;
  asset.precision = BigInt.fromI32(10).pow(6);
  asset.tokenAddress = Bytes.fromHexString(v.asset);
  asset.save();

  return v;
}

export function listManager(vault: Address, manager: Address): void {
  let isApproved = true;
  let newApprovedVaultEvent = createApprovedVaultEvent(manager, vault, isApproved);
  handleApprovedVault(newApprovedVaultEvent);
}

export function createApprovedVaultEvent(manager: Address, vault: Address, isApproved: boolean): ApprovedVault {
  let approvedVaultEvent = changetype<ApprovedVault>(newMockEvent());

  approvedVaultEvent.parameters = new Array();

  approvedVaultEvent.parameters.push(new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault)));
  approvedVaultEvent.parameters.push(new ethereum.EventParam("isApproved", ethereum.Value.fromBoolean(isApproved)));

  approvedVaultEvent.address = manager;

  return approvedVaultEvent;
}

export function createWithdrawRequestTokenizedEvent(
  manager: Address,
  from: Address,
  to: Address,
  vault: Address,
  requestId: BigInt,
  sharesAmount: BigInt,
): WithdrawRequestTokenized {
  let withdrawRequestTokenizedEvent = changetype<WithdrawRequestTokenized>(newMockEvent());

  withdrawRequestTokenizedEvent.parameters = new Array();

  withdrawRequestTokenizedEvent.parameters.push(new ethereum.EventParam("from", ethereum.Value.fromAddress(from)));
  withdrawRequestTokenizedEvent.parameters.push(new ethereum.EventParam("to", ethereum.Value.fromAddress(to)));
  withdrawRequestTokenizedEvent.parameters.push(new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault)));
  withdrawRequestTokenizedEvent.parameters.push(
    new ethereum.EventParam("requestId", ethereum.Value.fromUnsignedBigInt(requestId)),
  );
  withdrawRequestTokenizedEvent.parameters.push(
    new ethereum.EventParam("sharesAmount", ethereum.Value.fromUnsignedBigInt(sharesAmount)),
  );

  withdrawRequestTokenizedEvent.address = manager;

  return withdrawRequestTokenizedEvent;
}
