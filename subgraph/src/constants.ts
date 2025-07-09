import { Address, BigInt } from "@graphprotocol/graph-ts";

export const ZERO_ADDRESS = Address.zero();
export const UNDERLYING = "Underlying";
export const VAULT_SHARE = "VaultShare";
export const VAULT_DEBT = "VaultDebt";
export const FIAT = "Fiat";
export const DEFAULT_PRECISION = BigInt.fromI32(10).pow(18);