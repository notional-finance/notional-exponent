import { Address, BigInt } from "@graphprotocol/graph-ts";

export const ZERO_ADDRESS = Address.zero();
export const UNDERLYING = "Underlying";
export const VAULT_SHARE = "VaultShare";
export const VAULT_DEBT = "VaultDebt";
export const FIAT = "Fiat";
export const DEFAULT_PRECISION = BigInt.fromI32(10).pow(18);
export const TRADING_MODULE = Address.fromHexString("0x594734c7e06C3D483466ADBCe401C6Bd269746C8");
export const SECONDS_IN_YEAR = BigInt.fromI32(31536000);
export const RATE_PRECISION = BigInt.fromI32(10).pow(9);
export const SHARE_PRECISION = BigInt.fromI32(10).pow(24);
export const SHARE_DECIMALS = 24;
export const ADDRESS_REGISTRY = Address.fromHexString("0xe335d314BD4eF7DD44F103dC124FEFb7Ce63eC95");
export const USD_ASSET_ID = "0x000000000000000000000000000000000000F147";
