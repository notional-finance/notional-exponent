import { Address, ethereum, BigInt, Bytes } from "@graphprotocol/graph-ts";
import { Token, TradingModulePermission } from "../generated/schema";
import { PriceOracleUpdated, TokenPermissionsUpdated, ITradingModule } from "../generated/TradingModule/ITradingModule";
import { USD_ASSET_ID, ZERO_ADDRESS } from "./constants";
import { createERC20TokenAsset, getTokenNameAndSymbol } from "./entities/token";
import { IERC20Metadata } from "../generated/AddressRegistry/IERC20Metadata";
import { registerChainlinkOracle } from "./entities/oracles";

function getUSDAsset(event: ethereum.Event): Token {
  let token = Token.load(USD_ASSET_ID);
  if (token == null) {
    token = new Token(USD_ASSET_ID);
    token.name = "US Dollar";
    token.symbol = "USD";
    token.decimals = 8;
    token.precision = BigInt.fromI32(10).pow(8);

    token.tokenInterface = "FIAT";
    token.tokenAddress = Address.fromHexString(USD_ASSET_ID);
    token.tokenType = "Fiat";

    token.lastUpdateBlockNumber = event.block.number;
    token.lastUpdateTimestamp = event.block.timestamp.toI32();
    token.lastUpdateTransactionHash = event.transaction.hash;

    token.firstUpdateBlockNumber = event.block.number;
    token.firstUpdateTimestamp = event.block.timestamp.toI32();
    token.firstUpdateTransactionHash = event.transaction.hash;

    token.save();
  }

  return token as Token;
}

export function handlePriceOracleUpdate(event: PriceOracleUpdated): void {
  let usdBaseAsset = getUSDAsset(event);
  let quoteAsset = createERC20TokenAsset(event.params.token, event, "Underlying");
  registerChainlinkOracle(usdBaseAsset, quoteAsset, event.params.oracle, false, event);
}

export function handleInitialOracles(block: ethereum.Block): void {
  let trading = ITradingModule.bind(
    Address.fromBytes(Address.fromHexString("0x594734c7e06C3D483466ADBCe401C6Bd269746C8")),
  );

  // Creates an empty event for method compatibility
  let event = new ethereum.Event(
    trading._address,
    BigInt.zero(),
    BigInt.zero(),
    null,
    block,
    new ethereum.Transaction(
      Bytes.empty(),
      BigInt.zero(),
      trading._address,
      ZERO_ADDRESS,
      BigInt.zero(),
      BigInt.zero(),
      BigInt.zero(),
      Bytes.empty(),
      BigInt.zero(),
    ),
    new Array<ethereum.EventParam>(),
    null,
  );
  let initialQuoteAssets = [
    // ETH
    Address.fromHexString("0x0000000000000000000000000000000000000000"),
    // tBTC
    Address.fromHexString("0x18084fba666a33d37592fa2633fd49a74dd93a88"),
    // WBTC
    Address.fromHexString("0x2260fac5e5542a773aa44fbcfedf7c193bc2c599"),
    // GHO
    Address.fromHexString("0x40d16fc0246ad3160ccc09b8d0d3a2cd28ae6c2f"),
    // USDe
    Address.fromHexString("0x4c9edd5852cd905f086c759e8383e09bff1e68b3"),
    // DAI
    Address.fromHexString("0x6b175474e89094c44da98b954eedeac495271d0f"),
    // PYUSD
    Address.fromHexString("0x6c3ea9036406852006290770bedfcaba0e23a0e8"),
    // wstETH
    Address.fromHexString("0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0"),
    // sUSDe
    Address.fromHexString("0x9d39a5de30e57443bff2a8307a4256c8797a3497"),
    // USDC
    Address.fromHexString("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"),
    // rsETH
    Address.fromHexString("0xa1290d69c65a6fe4df752f95823fae25cb99e5a7"),
    // rETH
    Address.fromHexString("0xae78736cd615f374d3085123a210448e74fc6393"),
    // stETH
    Address.fromHexString("0xae7ab96520de3a18e5e111b5eaab095312d7fe84"),
    // BAL
    Address.fromHexString("0xba100000625a3754423978a60c9317c58a424e3d"),
    // ezETH
    Address.fromHexString("0xbf5495efe5db9ce00f80364c8b423567e58d2110"),
    // WETH
    Address.fromHexString("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"),
    // weETH
    Address.fromHexString("0xcd5fe23c85820f7b72d0926fc9b05b43e359b7ee"),
    // USDT
    Address.fromHexString("0xdac17f958d2ee523a2206206994597c13d831ec7"),
    // osETH
    Address.fromHexString("0xf1c9acdc66974dfb6decb12aa385b9cd01190e38"),
    // crvUSD
    Address.fromHexString("0xf939e0a03fb07f59a73314e73794be0e57ac1b4e"),
  ];
  let usdBaseAsset = getUSDAsset(event);

  for (let i = 0; i < initialQuoteAssets.length; i++) {
    let quoteAsset = createERC20TokenAsset(Address.fromBytes(initialQuoteAssets[i]), event, "Underlying");
    let oracle = trading.priceOracles(Address.fromBytes(initialQuoteAssets[i]));
    registerChainlinkOracle(usdBaseAsset, quoteAsset, oracle.getOracle(), false, event);
  }
}

function getTradingModulePermissions(sender: Address, token: Address, event: ethereum.Event): TradingModulePermission {
  let id = sender.toHexString() + ":" + token.toHexString();
  let permissions = TradingModulePermission.load(id);
  if (permissions == null) {
    permissions = new TradingModulePermission(id);
    permissions.sender = sender.toHexString();
    permissions.tokenAddress = token;
    permissions.allowedDexes = new Array<string>();
    permissions.allowedTradeTypes = new Array<string>();
    let nameSymbol = getTokenNameAndSymbol(IERC20Metadata.bind(token));
    permissions.name = nameSymbol[0];
    permissions.symbol = nameSymbol[1];

    let entity = Token.load(token.toHexString());
    if (entity != null) {
      // Only set the token link if the asset exists, otherwise just set the
      // token address
      permissions.token = token.toHexString();
    }
  }

  permissions.lastUpdateBlockNumber = event.block.number;
  permissions.lastUpdateTimestamp = event.block.timestamp.toI32();
  permissions.lastUpdateTransactionHash = event.transaction.hash;

  return permissions;
}

export function handleTokenPermissionsUpdate(event: TokenPermissionsUpdated): void {
  let permissions = getTradingModulePermissions(event.params.sender, event.params.token, event);
  permissions.allowSell = event.params.permissions.allowSell;
  let dexFlags = event.params.permissions.dexFlags.toI32();
  let dexes = new Array<string>();
  if ((dexFlags & 1) == 1) dexes.push("UNUSED");
  if ((dexFlags & 2) == 2) dexes.push("UNISWAP_V2");
  if ((dexFlags & 4) == 4) dexes.push("UNISWAP_V3");
  if ((dexFlags & 8) == 8) dexes.push("ZERO_EX");
  if ((dexFlags & 16) == 16) dexes.push("BALANCER_V2");
  if ((dexFlags & 32) == 32) dexes.push("CURVE");
  if ((dexFlags & 64) == 64) dexes.push("NOTIONAL_VAULT");
  if ((dexFlags & 128) == 128) dexes.push("CURVE_V2");
  permissions.allowedDexes = dexes;

  let tradeTypeFlags = event.params.permissions.tradeTypeFlags.toI32();
  let tradeType = new Array<string>();
  if ((tradeTypeFlags & 1) == 1) tradeType.push("EXACT_IN_SINGLE");
  if ((tradeTypeFlags & 2) == 2) tradeType.push("EXACT_OUT_SINGLE");
  if ((tradeTypeFlags & 4) == 4) tradeType.push("EXACT_IN_BATCH");
  if ((tradeTypeFlags & 8) == 8) tradeType.push("EXACT_OUT_BATCH");
  permissions.allowedTradeTypes = tradeType;

  permissions.save();
}
