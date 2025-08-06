import { Address, ethereum, Bytes, BigInt } from "@graphprotocol/graph-ts";
import { ExchangeRate, Oracle, OracleRegistry, Token } from "../../generated/schema";
import { getToken } from "./token";
import { IYieldStrategy } from "../../generated/AddressRegistry/IYieldStrategy";
import { DEFAULT_PRECISION, ZERO_ADDRESS } from "../constants";
import { ILendingRouter } from "../../generated/AddressRegistry/ILendingRouter";
import { Aggregator } from "../../generated/AddressRegistry/Aggregator";

const ORACLE_REGISTRY_ID = "0";
const SIX_HOURS = BigInt.fromI32(21_600);

export function getOracleRegistry(): OracleRegistry {
  let registry = OracleRegistry.load(ORACLE_REGISTRY_ID);
  if (registry == null) {
    registry = new OracleRegistry(ORACLE_REGISTRY_ID);
    registry.chainlinkOracles = new Array<string>();
    registry.listedVaults = new Array<Bytes>();
    registry.lendingRouters = new Array<Bytes>();
    registry.withdrawRequestManager = new Array<Bytes>();
    registry.lastRefreshBlockNumber = BigInt.fromI32(0);
    registry.lastRefreshTimestamp = 0;
    registry.save();
  }

  return registry as OracleRegistry;
}

export function updateChainlinkOracle(oracle: Oracle, block: ethereum.Block): void {
  let aggregator = Aggregator.bind(Address.fromBytes(oracle.oracleAddress));
  let latestRate = aggregator.try_latestAnswer();
  if (!latestRate.reverted) {
    let rate = oracle.mustInvert
      ? oracle.ratePrecision.times(oracle.ratePrecision).div(latestRate.value)
      : latestRate.value;

    updateExchangeRate(oracle, rate, block);
  }
}

export function updateVaultOracles(vault: Address, block: ethereum.Block, lendingRouters: Bytes[]): void {
  let v = IYieldStrategy.bind(vault);
  let asset = getToken(v.asset().toHexString());
  let vaultShare = getToken(vault.toHexString());
  let yieldToken = getToken(v.yieldToken().toHexString());

  // Vault share price
  let oracle = getOracle(asset, vaultShare, "VaultShareOracleRate");
  oracle.decimals = 36;
  oracle.ratePrecision = BigInt.fromI32(10).pow(36);
  oracle.oracleAddress = vault;
  let latestRate = v.price1(ZERO_ADDRESS);
  updateExchangeRate(oracle, latestRate, block);

  // Vault fee accumulator
  let oracle2 = getOracle(vaultShare, yieldToken, "VaultFeeAccrualRate");
  oracle2.decimals = 18;
  oracle2.ratePrecision = DEFAULT_PRECISION;
  oracle2.oracleAddress = vault;
  let latestRate2 = v.convertSharesToYieldToken(DEFAULT_PRECISION);
  updateExchangeRate(oracle2, latestRate2, block);

  for (let i = 0; i < lendingRouters.length; i++) {
    let l = ILendingRouter.bind(Address.fromBytes(lendingRouters[i]));
    let id = vault.toHexString() + ":" + Address.fromBytes(lendingRouters[i]).toHexString();
    let borrowShare = Token.load(id);
    if (borrowShare) {
      let latestRate = l.convertBorrowSharesToAssets(vault, borrowShare.precision);
      let borrowShareOracle = getOracle(borrowShare, asset, "BorrowShareOracleRate");
      borrowShareOracle.decimals = asset.decimals;
      borrowShareOracle.ratePrecision = asset.precision;
      borrowShareOracle.oracleAddress = l._address;
      updateExchangeRate(borrowShareOracle, latestRate, block);
    }
  }
}

function getOracle(base: Token, quote: Token, oracleType: string): Oracle {
  let id = base.id + ":" + quote.id + ":" + oracleType;
  let oracle = Oracle.load(id);
  if (oracle == null) {
    oracle = new Oracle(id);
    oracle.base = base.id;
    oracle.quote = quote.id;
    oracle.oracleType = oracleType;
    oracle.mustInvert = false;
    oracle.matured = false;
  }

  return oracle as Oracle;
}

function updateExchangeRate(oracle: Oracle, rate: BigInt, block: ethereum.Block): void {
  let ts = block.timestamp.minus(block.timestamp.mod(SIX_HOURS));
  let id = oracle.id + ":" + ts.toString();

  // Only save the exchange rate once per ID.
  if (ExchangeRate.load(id) === null) {
    let exchangeRate = new ExchangeRate(id);
    exchangeRate.blockNumber = block.number;
    exchangeRate.timestamp = block.timestamp.toI32();
    exchangeRate.rate = rate;
    exchangeRate.oracle = oracle.id;
    let quote = getToken(oracle.quote);
    // Snapshot the total supply figure for TVL calculations
    exchangeRate.totalSupply = quote.totalSupply;
    exchangeRate.save();

    oracle.latestRate = rate;
    oracle.lastUpdateBlockNumber = block.number;
    oracle.lastUpdateTimestamp = block.timestamp.toI32();
    oracle.save();
  }
}
