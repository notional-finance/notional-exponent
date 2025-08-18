import { Address, ethereum, BigInt, dataSource, Bytes } from "@graphprotocol/graph-ts";
import { Token, TradingModulePermission } from "../generated/schema";
import { PriceOracleUpdated, TokenPermissionsUpdated, ITradingModule } from "../generated/TradingModule/ITradingModule";
import { USD_ASSET_ID, ZERO_ADDRESS } from "./constants";
import { createERC20TokenAsset, getToken, getTokenNameAndSymbol } from "./entities/token";
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
  if (dataSource.network() == "mainnet") {
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
      Address.fromHexString("0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419"),
      // tBTC
      Address.fromHexString("0x8350b7de6a6a2c1368e7d4bd968190e13e354297"),
      // WBTC
      Address.fromHexString("0xf4030086522a5beea4988f8ca5b36dbc97bee88c"),
      // GHO
      Address.fromHexString("0x3f12643d3f6f874d39c2a4c9f2cd6f2dbac877fc"),
      // USDe
      Address.fromHexString("0xa569d910839ae8865da8f8e70fffb0cba869f961"),
      // DAI
      Address.fromHexString("0xaed0c38402a5d19df6e4c03f4e2dced6e29c1ee9"),
      // PYUSD
      Address.fromHexString("0x8f1df6d7f2db73eece86a18b4381f4707b918fb1"),
      // wstETH
      Address.fromHexString("0x8770d8deb4bc923bf929cd260280b5f1dd69564d"),
      // sUSDe
      Address.fromHexString("0xff3bc18ccbd5999ce63e788a1c250a88626ad099"),
      // USDC
      Address.fromHexString("0x8fffffd4afb6115b954bd326cbe7b4ba576818f6"),
      // rsETH
      Address.fromHexString("0xb676ea4e0a54ffd579effc1f1317c70d671f2028"),
      // rETH
      Address.fromHexString("0xa7d273951861cf07df8b0a1c3c934fd41ba9e8eb"),
      // stETH
      Address.fromHexString("0xcfe54b5cd566ab89272946f602d76ea879cab4a8"),
      // BAL
      Address.fromHexString("0xdf2917806e30300537aeb49a7663062f4d1f2b5f"),
      // ezETH
      Address.fromHexString("0xe1ffdc18be251e76fb0a1cbfa6d30692c374c5fc"),
      // WETH
      Address.fromHexString("0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419"),
      // weETH
      Address.fromHexString("0xe47f6c47de1f1d93d8da32309d4db90acdadeeae"),
      // USDT
      Address.fromHexString("0x3e7d1eab13ad0104d2750b8863b489d65364e32d"),
      // osETH
      Address.fromHexString("0x3d3d7d124b0b80674730e0d31004790559209deb"),
      // crvUSD
      Address.fromHexString("0xeef0c605546958c1f899b6fb336c20671f9cd49f"),
    ];
    let usdBaseAsset = getUSDAsset(event);

    for (let i = 0; i < initialQuoteAssets.length; i++) {
      let quoteAsset = createERC20TokenAsset(Address.fromBytes(initialQuoteAssets[i]), event, "Underlying");
      let oracle = trading.priceOracles(Address.fromBytes(initialQuoteAssets[i]));
      registerChainlinkOracle(usdBaseAsset, quoteAsset, oracle.getOracle(), false, event);
    }
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
