import { Address, BigInt, ethereum } from "@graphprotocol/graph-ts";
import { IERC20Metadata } from "../../generated/AddressRegistry/IERC20Metadata";
import { Token } from "../../generated/schema";
import { ZERO_ADDRESS } from "../constants";

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
  if (entity == null) {
    entity = new Token(id);
  }
  return entity as Token;
}

export function createERC20TokenAsset(
  tokenAddress: Address,
  event: ethereum.Event,
  tokenType: string
): Token {
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
    let decimals = erc20.decimals();
    token.name = symbolAndName[0];
    token.symbol = symbolAndName[1];
    token.decimals = decimals;
    token.precision = BigInt.fromI32(10).pow(decimals as u8);
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
  let id = vault.toHexString() + "-" + lendingRouter.toHexString();
  let borrowShare = Token.load(id);
  if (borrowShare) return borrowShare;

  // TODO: need to fill this out for real
  borrowShare = new Token(id);
  borrowShare.name = "Borrow Share";
  borrowShare.symbol = "Borrow Share";
  borrowShare.decimals = 18;
  borrowShare.precision = BigInt.fromI32(10).pow(18);
  borrowShare.tokenInterface = "ERC20";
  borrowShare.tokenAddress = lendingRouter;
  borrowShare.vaultAddress = vault;
  borrowShare.tokenType = "VaultDebt";

  borrowShare.lastUpdateBlockNumber = event.block.number;
  borrowShare.lastUpdateTimestamp = event.block.timestamp.toI32();
  borrowShare.lastUpdateTransactionHash = event.transaction.hash;

  borrowShare.firstUpdateBlockNumber = event.block.number;
  borrowShare.firstUpdateTimestamp = event.block.timestamp.toI32();
  borrowShare.firstUpdateTransactionHash = event.transaction.hash;

  borrowShare.save();

  return borrowShare;
}
