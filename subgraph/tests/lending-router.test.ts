import { describe, test, beforeAll, createMockedFunction, newMockEvent, logStore, newLog, assert } from "matchstick-as";
import { Address, ethereum, BigInt, ByteArray, crypto, Bytes } from "@graphprotocol/graph-ts";
import { createVault } from "./withdraw-request-manager.test";
import { DEFAULT_PRECISION } from "../src/constants";
import { EnterPosition } from "../generated/templates/LendingRouter/ILendingRouter";
import { handleEnterPosition } from "../src/lending-router";

let vault = Address.fromString("0x0000000000000000000000000000000000000001");
let lendingRouter = Address.fromString("0x00000000000000000000000000000000000000AA");
let account = Address.fromString("0x0000000000000000000000000000000000000AAA");
let accountingAsset = Address.fromString("0x00000000000000000000000000000000000000bb");
let asset = Address.fromString("0x00000000000000000000000000000000000000ff");
let yieldToken = Address.fromString("0x00000000000000000000000000000000000000ee");
let hash = Bytes.fromHexString("0x0000000000000000000000000000000000000000000000000000000000000009");
let USDC_PRECISION = BigInt.fromI32(10).pow(6);

function createEnterPositionEvent(
  user: Address,
  vault: Address,
  depositAssets: BigInt,
  borrowShares: BigInt,
  vaultSharesReceived: BigInt,
  wasMigrated: boolean,
): EnterPosition {
  let enterPositionEvent = changetype<EnterPosition>(newMockEvent());

  enterPositionEvent.parameters = new Array();

  enterPositionEvent.parameters.push(new ethereum.EventParam("user", ethereum.Value.fromAddress(user)));

  enterPositionEvent.parameters.push(new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault)));

  enterPositionEvent.parameters.push(
    new ethereum.EventParam("depositAssets", ethereum.Value.fromUnsignedBigInt(depositAssets)),
  );

  enterPositionEvent.parameters.push(
    new ethereum.EventParam("borrowShares", ethereum.Value.fromUnsignedBigInt(borrowShares)),
  );

  enterPositionEvent.parameters.push(
    new ethereum.EventParam("vaultSharesReceived", ethereum.Value.fromUnsignedBigInt(vaultSharesReceived)),
  );

  enterPositionEvent.parameters.push(new ethereum.EventParam("wasMigrated", ethereum.Value.fromBoolean(wasMigrated)));

  enterPositionEvent.address = lendingRouter;
  enterPositionEvent.transaction.hash = hash;
  enterPositionEvent.logIndex = BigInt.fromI32(3);

  return enterPositionEvent;
}

function baseMockFunctions(strategy: string): void {
  createMockedFunction(vault, "asset", "asset():(address)").returns([ethereum.Value.fromAddress(asset)]);

  createMockedFunction(vault, "accountingAsset", "accountingAsset():(address)").returns([
    ethereum.Value.fromAddress(accountingAsset),
  ]);

  createMockedFunction(vault, "yieldToken", "yieldToken():(address)").returns([ethereum.Value.fromAddress(yieldToken)]);

  createMockedFunction(vault, "strategy", "strategy():(string)").returns([ethereum.Value.fromString(strategy)]);

  createMockedFunction(lendingRouter, "name", "name():(string)").returns([ethereum.Value.fromString("Morpho")]);

  createMockedFunction(lendingRouter, "borrowShareDecimals", "borrowShareDecimals():(uint8)").returns([
    ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(18)),
  ]);
}

function mockVaultSharePrice(vaultShares: BigInt, price: BigInt): void {
  createMockedFunction(vault, "price", "price(address):(uint256)")
    .withArgs([ethereum.Value.fromAddress(account)])
    .returns([ethereum.Value.fromUnsignedBigInt(price.times(DEFAULT_PRECISION).div(USDC_PRECISION))]);

  createMockedFunction(vault, "convertToAssets", "convertToAssets(uint256):(uint256)")
    .withArgs([ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION)])
    .returns([ethereum.Value.fromUnsignedBigInt(price)]);

  createMockedFunction(lendingRouter, "balanceOfCollateral", "balanceOfCollateral(address,address):(uint256)")
    .withArgs([ethereum.Value.fromAddress(account), ethereum.Value.fromAddress(vault)])
    .returns([ethereum.Value.fromUnsignedBigInt(vaultShares)]);
}

function mockVaultFeePrice(): void {
  createMockedFunction(vault, "convertSharesToYieldToken", "convertSharesToYieldToken(uint256):(uint256)")
    .withArgs([ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION)])
    .returns([ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION.times(BigInt.fromI32(95)).div(BigInt.fromI32(100)))]);

  createMockedFunction(vault, "convertYieldTokenToShares", "convertYieldTokenToShares(uint256):(uint256)")
    .withArgs([ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION)])
    .returns([
      ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION.times(BigInt.fromI32(1000)).div(BigInt.fromI32(95))),
    ]);
}

function mockBorrowSharePrice(borrowShares: BigInt, borrowAssets: BigInt): void {
  createMockedFunction(lendingRouter, "balanceOfBorrowShares", "balanceOfBorrowShares(address,address):(uint256)")
    .withArgs([ethereum.Value.fromAddress(account), ethereum.Value.fromAddress(vault)])
    .returns([ethereum.Value.fromUnsignedBigInt(borrowShares)]);

  createMockedFunction(
    lendingRouter,
    "convertBorrowSharesToAssets",
    "convertBorrowSharesToAssets(address,uint256):(uint256)",
  )
    .withArgs([ethereum.Value.fromAddress(vault), ethereum.Value.fromUnsignedBigInt(borrowShares)])
    .returns([ethereum.Value.fromUnsignedBigInt(borrowAssets)]);
}

let vaultSharesMinted = DEFAULT_PRECISION.times(BigInt.fromI32(1000));
let borrowSharesMinted = DEFAULT_PRECISION.times(BigInt.fromI32(900));
// 0.99e18
let vaultSharePrice = DEFAULT_PRECISION.times(BigInt.fromI32(99)).div(BigInt.fromI32(100));

describe("enter position with borrow shares", () => {
  beforeAll(() => {
    createVault(vault);
    baseMockFunctions("CurveConvex2Token");

    mockVaultSharePrice(vaultSharesMinted, vaultSharePrice);
    mockBorrowSharePrice(
      borrowSharesMinted,
      borrowSharesMinted
        .times(USDC_PRECISION)
        .times(BigInt.fromI32(101))
        .div(BigInt.fromI32(100))
        .div(DEFAULT_PRECISION),
    );
    mockVaultFeePrice();

    let enterPositionEvent = createEnterPositionEvent(
      account,
      vault,
      BigInt.fromI32(100).times(USDC_PRECISION),
      borrowSharesMinted,
      vaultSharesMinted,
      false,
    );

    // Add TradeExecuted log
    let tradeExecutedLog = newLog();
    tradeExecutedLog.address = vault;
    tradeExecutedLog.topics = [
      Bytes.fromByteArray(crypto.keccak256(ByteArray.fromUTF8("TradeExecuted(address,address,uint256,uint256)"))),
      Bytes.fromHexString("0x00000000000000000000000000000000000000ff"),
      Bytes.fromHexString("0x00000000000000000000000000000000000000ff"),
    ];
    tradeExecutedLog.data = Bytes.fromByteArray(
      ByteArray.fromBigInt(DEFAULT_PRECISION).concat(ByteArray.fromBigInt(DEFAULT_PRECISION)),
    );

    let incentiveTransferLog = newLog();
    incentiveTransferLog.address = vault;
    incentiveTransferLog.topics = [
      Bytes.fromByteArray(crypto.keccak256(ByteArray.fromUTF8("VaultRewardTransfer(address,address,uint256)"))),
      Bytes.fromHexString("0x00000000000000000000000000000000000000ff"),
      Bytes.fromHexString(account.toHexString()),
    ];
    incentiveTransferLog.data = Bytes.fromByteArray(ByteArray.fromBigInt(DEFAULT_PRECISION));

    enterPositionEvent.receipt!.logs = [tradeExecutedLog, incentiveTransferLog];

    handleEnterPosition(enterPositionEvent);
  });

  test("has vault share profit loss line item", () => {
    let id = hash.toHexString() + ":" + BigInt.fromI32(3).toString() + ":" + vault.toHexString();
    assert.fieldEquals("ProfitLossLineItem", id, "lineItemType", "EnterPosition");
    assert.fieldEquals("ProfitLossLineItem", id, "account", account.toHexString());
    assert.fieldEquals("ProfitLossLineItem", id, "token", vault.toHexString());
    assert.fieldEquals("ProfitLossLineItem", id, "underlyingToken", asset.toHexString());
    assert.fieldEquals("ProfitLossLineItem", id, "tokenAmount", vaultSharesMinted.toString());
    assert.fieldEquals(
      "ProfitLossLineItem",
      id,
      "underlyingAmountRealized",
      // 1009e6
      BigInt.fromI32(1009).times(USDC_PRECISION).toString(),
    );
    assert.fieldEquals("ProfitLossLineItem", id, "realizedPrice", "1009000000000000000");
    assert.fieldEquals("ProfitLossLineItem", id, "spotPrice", vaultSharePrice.toString());
    assert.fieldEquals(
      "ProfitLossLineItem",
      id,
      "underlyingAmountSpot",
      // 990e6
      BigInt.fromI32(990).times(USDC_PRECISION).toString(),
    );
  });

  test("has borrow share profit loss line item", () => {
    let borrowShareToken = vault.toHexString() + ":" + lendingRouter.toHexString();
    let id = hash.toHexString() + ":" + BigInt.fromI32(3).toString() + ":" + borrowShareToken;
    assert.fieldEquals("ProfitLossLineItem", id, "lineItemType", "EnterPosition");
    assert.fieldEquals("ProfitLossLineItem", id, "account", account.toHexString());
    assert.fieldEquals("ProfitLossLineItem", id, "token", borrowShareToken);
    assert.fieldEquals("ProfitLossLineItem", id, "underlyingToken", asset.toHexString());

    assert.fieldEquals("ProfitLossLineItem", id, "tokenAmount", borrowSharesMinted.toString());
    assert.fieldEquals(
      "ProfitLossLineItem",
      id,
      "underlyingAmountRealized",
      BigInt.fromI32(909).times(USDC_PRECISION).toString(),
    );

    assert.fieldEquals("ProfitLossLineItem", id, "realizedPrice", "1010000000000000000");
    assert.fieldEquals("ProfitLossLineItem", id, "spotPrice", "1010000000000000000");

    assert.fieldEquals(
      "ProfitLossLineItem",
      id,
      "underlyingAmountSpot",
      BigInt.fromI32(909).times(USDC_PRECISION).toString(),
    );
  });

  test("has vault share balance", () => {});
  test("has borrow share balance", () => {});
  test("has trade execution line items", () => {});
  test("incentive snapshot line items", () => {});

  test("vault share fees paid", () => {});

  test("staking interest accrued", () => {});

  test("pendle pt interest accrued", () => {});
});

describe("enter position with no borrow shares", () => {});

describe("exit position with no assets repaid", () => {});

describe("exit position with assets repaid", () => {});

describe("initiate withdraw request", () => {});

describe("liquidate position", () => {});
