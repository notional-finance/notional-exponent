import { Address, BigInt, ethereum, log } from "@graphprotocol/graph-ts";
import { IERC20Metadata } from "../../generated/AddressRegistry/IERC20Metadata";
import { Token } from "../../generated/schema";
import { ZERO_ADDRESS } from "../constants";
import { ILendingRouter } from "../../generated/templates/LendingRouter/ILendingRouter";
import { IYieldStrategy } from "../../generated/templates/LendingRouter/IYieldStrategy";

export function getTokenNameAndSymbol(erc20: IERC20Metadata): string[] {
  let nameResult = erc20.try_name();
  let name: string;
  let symbol: string;
  if (nameResult.reverted) {
    name = "unknown";
  } else {
    name = nameResult.value;
  }

  let symbolResult = erc20.try_symbol();
  if (symbolResult.reverted) {
    symbol = "unknown";
  } else {
    symbol = symbolResult.value;
  }

  return [name, symbol];
}

export function getToken(id: string): Token {
  let entity = Token.load(id);
  if (entity == null) log.error("Token not found: {}", [id]);
  return entity as Token;
}

export function createERC20TokenAsset(tokenAddress: Address, event: ethereum.Event, tokenType: string): Token {
  let token = Token.load(tokenAddress.toHexString());
  if (token) return token;

  // If token does not exist, then create it here
  token = new Token(tokenAddress.toHexString());

  if (tokenAddress == ZERO_ADDRESS) {
    token.name = "Ether";
    token.symbol = "ETH";
    token.decimals = 18;
    token.precision = BigInt.fromI32(10).pow(18);
  } else {
    let erc20 = IERC20Metadata.bind(tokenAddress);
    let symbolAndName = getTokenNameAndSymbol(erc20);
    let decimalsResult = erc20.try_decimals();
    let decimals: i32;
    if (decimalsResult.reverted) {
      // This only happens for convex yield tokens, but they are known to be 18 decimals
      decimals = 18;
    } else {
      decimals = decimalsResult.value;
    }

    token.name = symbolAndName[0];
    token.symbol = symbolAndName[1];
    token.decimals = decimals;
    token.precision = BigInt.fromI32(10).pow(decimals as u8);
  }

  // Need to override the decimals for the two initially deployed vaults
  if (
    tokenAddress == Address.fromHexString("0xaf14d06a65c91541a5b2db627ecd1c92d7d9c48b") ||
    tokenAddress == Address.fromHexString("0x7f723fee1e65a7d26be51a05af0b5efee4a7d5ae")
  ) {
    token.decimals = 24;
    token.precision = BigInt.fromI32(10).pow(24 as u8);
  }

  token.tokenInterface = "ERC20";
  token.tokenAddress = tokenAddress;
  token.tokenType = tokenType;

  token.lastUpdateBlockNumber = event.block.number;
  token.lastUpdateTimestamp = event.block.timestamp.toI32();
  token.lastUpdateTransactionHash = event.transaction.hash;

  token.firstUpdateBlockNumber = event.block.number;
  token.firstUpdateTimestamp = event.block.timestamp.toI32();
  token.firstUpdateTransactionHash = event.transaction.hash;

  token.save();

  return token;
}

export function getBorrowShare(vault: Address, lendingRouter: Address, event: ethereum.Event): Token {
  let id = vault.toHexString() + ":" + lendingRouter.toHexString();
  let borrowShare = Token.load(id);
  if (borrowShare) return borrowShare;
  let l = ILendingRouter.bind(lendingRouter);
  let name = l.name();
  let decimals = 18;
  let v = IYieldStrategy.bind(Address.fromBytes(vault));
  let asset = getToken(v.asset().toHexString());

  if (name == "Morpho") {
    // Morpho borrow shares are 6 decimals more than the asset to account
    // for the virtual shares.
    decimals = asset.decimals + 6;
  }

  borrowShare = new Token(id);
  borrowShare.name = name + ":" + vault.toHexString();
  borrowShare.symbol = name + ":" + vault.toHexString();
  borrowShare.decimals = decimals;
  borrowShare.precision = BigInt.fromI32(10).pow(decimals as u8);
  borrowShare.tokenInterface = "ERC1155";
  borrowShare.tokenAddress = lendingRouter;
  borrowShare.vaultAddress = vault.toHexString();
  borrowShare.tokenType = "VaultDebt";
  borrowShare.underlying = asset.id;

  borrowShare.lastUpdateBlockNumber = event.block.number;
  borrowShare.lastUpdateTimestamp = event.block.timestamp.toI32();
  borrowShare.lastUpdateTransactionHash = event.transaction.hash;

  borrowShare.firstUpdateBlockNumber = event.block.number;
  borrowShare.firstUpdateTimestamp = event.block.timestamp.toI32();
  borrowShare.firstUpdateTransactionHash = event.transaction.hash;

  borrowShare.save();

  return borrowShare;
}
