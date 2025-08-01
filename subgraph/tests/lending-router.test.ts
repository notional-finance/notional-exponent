import {
  describe,
  test,
  beforeAll,
  createMockedFunction,
  newMockEvent,
  afterAll,
  newLog,
  assert,
  clearStore,
  log,
} from "matchstick-as";
import { Address, ethereum, BigInt, ByteArray, crypto, Bytes } from "@graphprotocol/graph-ts";
import {
  createVault,
  createInitiateWithdrawRequestEvent,
  listManager,
  createWithdrawRequestTokenizedEvent,
  createWithdrawRequestFinalizedEvent,
} from "./common";
import { DEFAULT_PRECISION, SECONDS_IN_YEAR } from "../src/constants";
import { EnterPosition, ExitPosition, LiquidatePosition } from "../generated/templates/LendingRouter/ILendingRouter";
import { handleEnterPosition, handleExitPosition, handleLiquidatePosition } from "../src/lending-router";
import { BalanceSnapshot, Token } from "../generated/schema";
import {
  handleInitiateWithdrawRequest,
  handleWithdrawRequestFinalized,
  handleWithdrawRequestTokenized,
} from "../src/withdraw-request-manager";

let vault = Address.fromString("0x0000000000000000000000000000000000000001");
let lendingRouter = Address.fromString("0x00000000000000000000000000000000000000AA");
let account = Address.fromString("0x0000000000000000000000000000000000000AAA");
let accountingAsset = Address.fromString("0x00000000000000000000000000000000000000bb");
let asset = Address.fromString("0x00000000000000000000000000000000000000ff");
let yieldToken = Address.fromString("0x00000000000000000000000000000000000000ee");
let hash = Bytes.fromHexString("0x0000000000000000000000000000000000000000000000000000000000000009");
let hash2 = Bytes.fromHexString("0x000000000000000000000000000000000000000000000000000000000000000A");
let hash3 = Bytes.fromHexString("0x000000000000000000000000000000000000000000000000000000000000000B");
let hash4 = Bytes.fromHexString("0x000000000000000000000000000000000000000000000000000000000000000C");
let hash5 = Bytes.fromHexString("0x000000000000000000000000000000000000000000000000000000000000000D");
let hash6 = Bytes.fromHexString("0x000000000000000000000000000000000000000000000000000000000000000E");
let hash7 = Bytes.fromHexString("0x000000000000000000000000000000000000000000000000000000000000000F");
let liquidator = Address.fromString("0x0000000000000000000000000000000000000bbb");
let manager = Address.fromString("0x0000000000000000000000000000000000000ccc");
let USDC_PRECISION = BigInt.fromI32(10).pow(6);
let BORROW_SHARE_PRECISION = BigInt.fromI32(10).pow(12);

function padHexString(hexString: string): string {
  return "0x" + hexString.slice(2).padStart(64, "0");
}

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

function createExitPositionEvent(
  user: Address,
  vault: Address,
  borrowSharesRepaid: BigInt,
  vaultSharesBurned: BigInt,
  profitsWithdrawn: BigInt,
): ExitPosition {
  let exitPositionEvent = changetype<ExitPosition>(newMockEvent());

  exitPositionEvent.parameters = new Array();

  exitPositionEvent.parameters.push(new ethereum.EventParam("user", ethereum.Value.fromAddress(user)));

  exitPositionEvent.parameters.push(new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault)));

  exitPositionEvent.parameters.push(
    new ethereum.EventParam("borrowSharesRepaid", ethereum.Value.fromUnsignedBigInt(borrowSharesRepaid)),
  );

  exitPositionEvent.parameters.push(
    new ethereum.EventParam("vaultSharesBurned", ethereum.Value.fromUnsignedBigInt(vaultSharesBurned)),
  );

  exitPositionEvent.parameters.push(
    new ethereum.EventParam("profitsWithdrawn", ethereum.Value.fromUnsignedBigInt(profitsWithdrawn)),
  );

  exitPositionEvent.address = lendingRouter;
  exitPositionEvent.transaction.hash = hash;
  exitPositionEvent.logIndex = BigInt.fromI32(3);

  return exitPositionEvent;
}

function createLiquidatePositionEvent(
  liquidator: Address,
  user: Address,
  vault: Address,
  borrowSharesRepaid: BigInt,
  vaultSharesToLiquidator: BigInt,
): LiquidatePosition {
  let liquidatePositionEvent = changetype<LiquidatePosition>(newMockEvent());

  liquidatePositionEvent.parameters = new Array();

  liquidatePositionEvent.parameters.push(new ethereum.EventParam("liquidator", ethereum.Value.fromAddress(liquidator)));

  liquidatePositionEvent.parameters.push(new ethereum.EventParam("user", ethereum.Value.fromAddress(user)));

  liquidatePositionEvent.parameters.push(new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault)));

  liquidatePositionEvent.parameters.push(
    new ethereum.EventParam("borrowSharesRepaid", ethereum.Value.fromUnsignedBigInt(borrowSharesRepaid)),
  );

  liquidatePositionEvent.parameters.push(
    new ethereum.EventParam("vaultSharesToLiquidator", ethereum.Value.fromUnsignedBigInt(vaultSharesToLiquidator)),
  );

  liquidatePositionEvent.address = lendingRouter;
  liquidatePositionEvent.logIndex = BigInt.fromI32(3);

  return liquidatePositionEvent;
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

  createMockedFunction(vault, "price", "price(address):(uint256)")
    .withArgs([ethereum.Value.fromAddress(liquidator)])
    .returns([ethereum.Value.fromUnsignedBigInt(price.times(DEFAULT_PRECISION).div(USDC_PRECISION))]);

  createMockedFunction(vault, "convertToAssets", "convertToAssets(uint256):(uint256)")
    .withArgs([ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION)])
    .returns([ethereum.Value.fromUnsignedBigInt(price.times(USDC_PRECISION).div(DEFAULT_PRECISION))]);

  createMockedFunction(lendingRouter, "balanceOfCollateral", "balanceOfCollateral(address,address):(uint256)")
    .withArgs([ethereum.Value.fromAddress(account), ethereum.Value.fromAddress(vault)])
    .returns([ethereum.Value.fromUnsignedBigInt(vaultShares)]);

  createMockedFunction(yieldToken, "name", "name():(string)").returns([ethereum.Value.fromString("Yield Token")]);
  createMockedFunction(yieldToken, "symbol", "symbol():(string)").returns([ethereum.Value.fromString("YT")]);
  createMockedFunction(yieldToken, "decimals", "decimals():(uint8)").returns([
    ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(18)),
  ]);
}

function mockVaultFeePrice(bps: BigInt): void {
  createMockedFunction(vault, "convertSharesToYieldToken", "convertSharesToYieldToken(uint256):(uint256)")
    .withArgs([ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION)])
    .returns([
      ethereum.Value.fromUnsignedBigInt(
        DEFAULT_PRECISION.times(BigInt.fromI32(10_000).minus(bps)).div(BigInt.fromI32(10_000)),
      ),
    ]);
}

function mockBorrowSharePrice(totalBorrowShares: BigInt, borrowShares: BigInt, borrowAssets: BigInt): void {
  createMockedFunction(lendingRouter, "balanceOfBorrowShares", "balanceOfBorrowShares(address,address):(uint256)")
    .withArgs([ethereum.Value.fromAddress(account), ethereum.Value.fromAddress(vault)])
    .returns([ethereum.Value.fromUnsignedBigInt(totalBorrowShares)]);

  createMockedFunction(
    lendingRouter,
    "convertBorrowSharesToAssets",
    "convertBorrowSharesToAssets(address,uint256):(uint256)",
  )
    .withArgs([ethereum.Value.fromAddress(vault), ethereum.Value.fromUnsignedBigInt(borrowShares)])
    .returns([ethereum.Value.fromUnsignedBigInt(borrowAssets)]);
}

let vaultSharesMinted = DEFAULT_PRECISION.times(BigInt.fromI32(1000));
let borrowSharesMinted = BORROW_SHARE_PRECISION.times(BigInt.fromI32(900));
// 0.99e18
let vaultSharePrice = DEFAULT_PRECISION.times(BigInt.fromI32(99)).div(BigInt.fromI32(100));

describe("enter position with borrow shares", () => {
  beforeAll(() => {
    createVault(vault);
    baseMockFunctions("CurveConvex2Token");

    mockVaultSharePrice(vaultSharesMinted, vaultSharePrice);
    mockBorrowSharePrice(
      borrowSharesMinted,
      borrowSharesMinted,
      borrowSharesMinted
        .times(USDC_PRECISION)
        .times(BigInt.fromI32(101))
        .div(BigInt.fromI32(100))
        .div(BORROW_SHARE_PRECISION),
    );
    mockVaultFeePrice(BigInt.fromI32(0));

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
    log.info("padded asset {}", [padHexString(asset.toHexString())]);
    tradeExecutedLog.topics = [
      Bytes.fromByteArray(crypto.keccak256(ByteArray.fromUTF8("TradeExecuted(address,address,uint256,uint256)"))),
      Bytes.fromHexString(padHexString(asset.toHexString())),
      Bytes.fromHexString(padHexString(yieldToken.toHexString())),
    ];
    tradeExecutedLog.data = ethereum.encode(
      ethereum.Value.fromTuple(
        changetype<ethereum.Tuple>([
          ethereum.Value.fromUnsignedBigInt(USDC_PRECISION.times(BigInt.fromI32(10))),
          ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION.times(BigInt.fromI32(9))),
        ]),
      ),
    )!;

    let incentiveTransferLog = newLog();
    incentiveTransferLog.address = vault;
    incentiveTransferLog.topics = [
      Bytes.fromByteArray(crypto.keccak256(ByteArray.fromUTF8("VaultRewardTransfer(address,address,uint256)"))),
      Bytes.fromHexString(padHexString(asset.toHexString())),
      Bytes.fromHexString(padHexString(account.toHexString())),
    ];
    incentiveTransferLog.data = ethereum.encode(ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION))!;

    enterPositionEvent.receipt!.logs = [tradeExecutedLog, incentiveTransferLog];

    handleEnterPosition(enterPositionEvent);
  });

  test("has vault share profit loss line item", () => {
    let id =
      hash.toHexString() + ":" + BigInt.fromI32(3).toString() + ":" + account.toHexString() + ":" + vault.toHexString();
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
    let id =
      hash.toHexString() + ":" + BigInt.fromI32(3).toString() + ":" + account.toHexString() + ":" + borrowShareToken;
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

  test("has vault share balance", () => {
    let id = account.toHexString() + ":" + vault.toHexString();
    assert.fieldEquals("Balance", id, "token", vault.toHexString());
    assert.fieldEquals("Balance", id, "account", account.toHexString());

    let snapshotId = id + ":" + BigInt.fromI32(1).toString();
    let snapshot = BalanceSnapshot.load(snapshotId);
    if (snapshot === null) assert.assertTrue(false, "snapshot is null");
    assert.assertTrue((snapshot as BalanceSnapshot).previousSnapshot === null);

    assert.fieldEquals("BalanceSnapshot", snapshotId, "currentBalance", vaultSharesMinted.toString());
    assert.fieldEquals("BalanceSnapshot", snapshotId, "previousBalance", BigInt.zero().toString());
    assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedBalance", vaultSharesMinted.toString());
    assert.fieldEquals(
      "BalanceSnapshot",
      snapshotId,
      "_accumulatedCostRealized",
      BigInt.fromI32(1009).times(USDC_PRECISION).toString(),
    );
    assert.fieldEquals(
      "BalanceSnapshot",
      snapshotId,
      "adjustedCostBasis",
      BigInt.fromI32(1009).times(USDC_PRECISION).div(BigInt.fromI32(1000)).toString(),
    );
    // Negative PnL includes loss from the initial deposit
    assert.fieldEquals("BalanceSnapshot", snapshotId, "currentProfitAndLossAtSnapshot", "-19000000");
    // These should both be zero at the first snapshot
    assert.fieldEquals("BalanceSnapshot", snapshotId, "totalInterestAccrualAtSnapshot", BigInt.zero().toString());
    assert.fieldEquals("BalanceSnapshot", snapshotId, "totalVaultFeesAtSnapshot", BigInt.zero().toString());
    assert.fieldEquals(
      "BalanceSnapshot",
      snapshotId,
      "_lastInterestAccumulator",
      vaultSharePrice.times(USDC_PRECISION).div(DEFAULT_PRECISION).toString(),
    );

    assert.fieldEquals("BalanceSnapshot", snapshotId, "_lastVaultFeeAccumulator", DEFAULT_PRECISION.toString());
  });

  test("has borrow share balance", () => {
    let borrowShareToken = vault.toHexString() + ":" + lendingRouter.toHexString();
    let id = account.toHexString() + ":" + borrowShareToken;
    assert.fieldEquals("Balance", id, "token", borrowShareToken);
    assert.fieldEquals("Balance", id, "account", account.toHexString());

    let snapshotId = id + ":" + BigInt.fromI32(1).toString();
    let snapshot = BalanceSnapshot.load(snapshotId);
    if (snapshot === null) assert.assertTrue(false, "snapshot is null");
    assert.assertTrue((snapshot as BalanceSnapshot).previousSnapshot === null);

    assert.fieldEquals("BalanceSnapshot", snapshotId, "currentBalance", borrowSharesMinted.toString());
    assert.fieldEquals("BalanceSnapshot", snapshotId, "previousBalance", BigInt.zero().toString());
    assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedBalance", borrowSharesMinted.toString());
    assert.fieldEquals(
      "BalanceSnapshot",
      snapshotId,
      "_accumulatedCostRealized",
      BigInt.fromI32(909).times(USDC_PRECISION).toString(),
    );
    assert.fieldEquals(
      "BalanceSnapshot",
      snapshotId,
      "adjustedCostBasis",
      BigInt.fromI32(1010).times(USDC_PRECISION).div(BigInt.fromI32(1000)).toString(),
    );

    // These are all supposed to be zero at the initial snapshot
    assert.fieldEquals("BalanceSnapshot", snapshotId, "currentProfitAndLossAtSnapshot", BigInt.zero().toString());
    assert.fieldEquals("BalanceSnapshot", snapshotId, "totalInterestAccrualAtSnapshot", BigInt.zero().toString());
    assert.fieldEquals("BalanceSnapshot", snapshotId, "_lastInterestAccumulator", BigInt.zero().toString());
    assert.fieldEquals("BalanceSnapshot", snapshotId, "totalVaultFeesAtSnapshot", BigInt.zero().toString());
    assert.fieldEquals("BalanceSnapshot", snapshotId, "_lastVaultFeeAccumulator", BigInt.zero().toString());
  });

  test("has trade execution line items", () => {
    let id =
      hash.toHexString() + ":" + BigInt.fromI32(0).toString() + ":" + account.toHexString() + ":" + asset.toHexString();
    assert.fieldEquals("ProfitLossLineItem", id, "lineItemType", "TradeExecution");
    assert.fieldEquals("ProfitLossLineItem", id, "account", account.toHexString());
    assert.fieldEquals("ProfitLossLineItem", id, "token", asset.toHexString());
    assert.fieldEquals("ProfitLossLineItem", id, "underlyingToken", yieldToken.toHexString());
    assert.fieldEquals("ProfitLossLineItem", id, "tokenAmount", USDC_PRECISION.times(BigInt.fromI32(10)).toString());
    assert.fieldEquals("ProfitLossLineItem", id, "underlyingAmountRealized", "9000000000000000000");
    assert.fieldEquals("ProfitLossLineItem", id, "realizedPrice", "900000000000000000");
    assert.fieldEquals("ProfitLossLineItem", id, "spotPrice", BigInt.zero().toString());
    assert.fieldEquals("ProfitLossLineItem", id, "underlyingAmountSpot", BigInt.zero().toString());
  });

  test("incentive snapshot line items", () => {
    let id =
      account.toHexString() +
      ":" +
      vault.toHexString() +
      ":" +
      BigInt.fromI32(1).toString() +
      ":" +
      asset.toHexString();
    assert.fieldEquals("IncentiveSnapshot", id, "rewardToken", asset.toHexString());
    assert.fieldEquals("IncentiveSnapshot", id, "totalClaimed", DEFAULT_PRECISION.toString());
    assert.fieldEquals("IncentiveSnapshot", id, "adjustedClaimed", DEFAULT_PRECISION.toString());
  });

  describe("test second entry", () => {
    beforeAll(() => {
      let vaultSharesMinted2 = BigInt.fromI32(99).times(DEFAULT_PRECISION);
      let vaultSharePrice2 = vaultSharePrice.plus(BigInt.fromI32(10).pow(16));

      let enterPositionEvent = createEnterPositionEvent(
        account,
        vault,
        BigInt.fromI32(100).times(USDC_PRECISION),
        BigInt.zero(),
        vaultSharesMinted2,
        false,
      );
      mockVaultSharePrice(vaultSharesMinted.plus(vaultSharesMinted2), vaultSharePrice2);
      mockVaultFeePrice(BigInt.fromI32(10));

      let incentiveTransferLog = newLog();
      incentiveTransferLog.address = vault;
      incentiveTransferLog.topics = [
        Bytes.fromByteArray(crypto.keccak256(ByteArray.fromUTF8("VaultRewardTransfer(address,address,uint256)"))),
        Bytes.fromHexString(padHexString(asset.toHexString())),
        Bytes.fromHexString(padHexString(account.toHexString())),
      ];
      incentiveTransferLog.data = ethereum.encode(
        ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION.times(BigInt.fromI32(2))),
      )!;

      enterPositionEvent.receipt!.logs = [incentiveTransferLog];
      enterPositionEvent.block.number = BigInt.fromI32(2);
      enterPositionEvent.block.timestamp = enterPositionEvent.block.timestamp.plus(BigInt.fromI32(3600));
      enterPositionEvent.transaction.hash = hash2;
      handleEnterPosition(enterPositionEvent);
    });

    test("has vault share balance after second entry", () => {
      let id = account.toHexString() + ":" + vault.toHexString();
      assert.fieldEquals("Balance", id, "token", vault.toHexString());
      assert.fieldEquals("Balance", id, "account", account.toHexString());

      let snapshotId = id + ":" + BigInt.fromI32(2).toString();
      let snapshot = BalanceSnapshot.load(snapshotId);
      if (snapshot === null) assert.assertTrue(false, "snapshot is null");
      assert.assertTrue((snapshot as BalanceSnapshot).previousSnapshot !== null);
      let vaultSharesMinted2 = BigInt.fromI32(99).times(DEFAULT_PRECISION);
      let vaultSharePrice2 = vaultSharePrice.plus(BigInt.fromI32(10).pow(16));
      let currentBalance = vaultSharesMinted.plus(vaultSharesMinted2);

      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "previousBalance", vaultSharesMinted.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedBalance", currentBalance.toString());
      assert.fieldEquals(
        "BalanceSnapshot",
        snapshotId,
        "_accumulatedCostRealized",
        BigInt.fromI32(1109).times(USDC_PRECISION).toString(),
      );
      assert.fieldEquals("BalanceSnapshot", snapshotId, "adjustedCostBasis", "1009099");
      // Negative PnL includes loss from the initial deposit
      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentProfitAndLossAtSnapshot", "-10000000");

      // 1000e18 * 0.01 = 10e18 interest accrued
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalInterestAccrualAtSnapshot", "10000000");
      // 1000e18 * 0.001 = 1e18 vault fees accrued
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalVaultFeesAtSnapshot", "1000000000000000000");
      assert.fieldEquals(
        "BalanceSnapshot",
        snapshotId,
        "_lastInterestAccumulator",
        vaultSharePrice2.times(USDC_PRECISION).div(DEFAULT_PRECISION).toString(),
      );
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_lastVaultFeeAccumulator", "999000000000000000");
    });

    test("incentive snapshot line items", () => {
      let id =
        account.toHexString() +
        ":" +
        vault.toHexString() +
        ":" +
        BigInt.fromI32(2).toString() +
        ":" +
        asset.toHexString();
      assert.fieldEquals("IncentiveSnapshot", id, "rewardToken", asset.toHexString());
      assert.fieldEquals(
        "IncentiveSnapshot",
        id,
        "totalClaimed",
        DEFAULT_PRECISION.times(BigInt.fromI32(3)).toString(),
      );
      assert.fieldEquals(
        "IncentiveSnapshot",
        id,
        "adjustedClaimed",
        DEFAULT_PRECISION.times(BigInt.fromI32(3)).toString(),
      );
    });

    test("has vault share profit loss line item", () => {
      let id =
        hash2.toHexString() +
        ":" +
        BigInt.fromI32(3).toString() +
        ":" +
        account.toHexString() +
        ":" +
        vault.toHexString();
      let vaultSharesMinted2 = BigInt.fromI32(99).times(DEFAULT_PRECISION);
      let vaultSharePrice2 = vaultSharePrice.plus(BigInt.fromI32(10).pow(16));
      assert.fieldEquals("ProfitLossLineItem", id, "lineItemType", "EnterPosition");
      assert.fieldEquals("ProfitLossLineItem", id, "account", account.toHexString());
      assert.fieldEquals("ProfitLossLineItem", id, "token", vault.toHexString());
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingToken", asset.toHexString());
      assert.fieldEquals("ProfitLossLineItem", id, "tokenAmount", vaultSharesMinted2.toString());
      assert.fieldEquals(
        "ProfitLossLineItem",
        id,
        "underlyingAmountRealized",
        // 100e6
        BigInt.fromI32(100).times(USDC_PRECISION).toString(),
      );
      assert.fieldEquals("ProfitLossLineItem", id, "realizedPrice", "1010101010101010101");
      assert.fieldEquals("ProfitLossLineItem", id, "spotPrice", vaultSharePrice2.toString());
      assert.fieldEquals(
        "ProfitLossLineItem",
        id,
        "underlyingAmountSpot",
        BigInt.fromI32(99).times(USDC_PRECISION).toString(),
      );
    });

    test("no borrow share profit loss line item or balance snapshot after second entry", () => {
      let borrowShareToken = vault.toHexString() + ":" + lendingRouter.toHexString();
      let id = hash2.toHexString() + ":" + BigInt.fromI32(3).toString() + ":" + borrowShareToken;
      assert.notInStore("ProfitLossLineItem", id);

      let snapshotId = account.toHexString() + ":" + borrowShareToken + ":" + BigInt.fromI32(2).toString();
      assert.notInStore("BalanceSnapshot", snapshotId);
    });

    test("pendle pt interest accrued", () => {});
  });

  describe("test exit position with assets repaid", () => {
    beforeAll(() => {
      let initialVaultShares = BigInt.fromI32(1099).times(DEFAULT_PRECISION);
      let vaultSharesBurned = BigInt.fromI32(100).times(DEFAULT_PRECISION);
      let vaultSharePrice2 = vaultSharePrice.plus(BigInt.fromI32(10).pow(16));
      let profitsWithdrawn = BigInt.fromI32(10).times(USDC_PRECISION);
      let borrowSharesRepaid = BigInt.fromI32(90).times(BORROW_SHARE_PRECISION);

      let exitPositionEvent = createExitPositionEvent(
        account,
        vault,
        borrowSharesRepaid,
        vaultSharesBurned,
        profitsWithdrawn,
      );

      mockVaultSharePrice(initialVaultShares.minus(vaultSharesBurned), vaultSharePrice2);
      mockVaultFeePrice(BigInt.fromI32(10));
      mockBorrowSharePrice(
        borrowSharesMinted.minus(borrowSharesRepaid),
        borrowSharesRepaid,
        borrowSharesRepaid
          .times(USDC_PRECISION)
          .times(BigInt.fromI32(102))
          .div(BigInt.fromI32(100))
          .div(BORROW_SHARE_PRECISION),
      );

      let incentiveTransferLog = newLog();
      incentiveTransferLog.address = vault;
      incentiveTransferLog.topics = [
        Bytes.fromByteArray(crypto.keccak256(ByteArray.fromUTF8("VaultRewardTransfer(address,address,uint256)"))),
        Bytes.fromHexString(padHexString(asset.toHexString())),
        Bytes.fromHexString(padHexString(account.toHexString())),
      ];
      incentiveTransferLog.data = ethereum.encode(
        ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION.times(BigInt.fromI32(2))),
      )!;

      exitPositionEvent.receipt!.logs = [incentiveTransferLog];
      exitPositionEvent.block.number = BigInt.fromI32(3);
      exitPositionEvent.block.timestamp = exitPositionEvent.block.timestamp.plus(BigInt.fromI32(3600));
      exitPositionEvent.transaction.hash = hash3;

      handleExitPosition(exitPositionEvent);
    });

    test("has profit loss line item after exit position", () => {
      let id =
        hash3.toHexString() +
        ":" +
        BigInt.fromI32(3).toString() +
        ":" +
        account.toHexString() +
        ":" +
        vault.toHexString();
      let vaultSharePrice2 = vaultSharePrice.plus(BigInt.fromI32(10).pow(16));
      let vaultSharesBurned = BigInt.fromI32(100).times(DEFAULT_PRECISION);

      assert.fieldEquals("ProfitLossLineItem", id, "lineItemType", "ExitPosition");
      assert.fieldEquals("ProfitLossLineItem", id, "account", account.toHexString());
      assert.fieldEquals("ProfitLossLineItem", id, "token", vault.toHexString());
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingToken", asset.toHexString());
      assert.fieldEquals("ProfitLossLineItem", id, "tokenAmount", vaultSharesBurned.neg().toString());
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingAmountRealized", "-101800000");
      assert.fieldEquals("ProfitLossLineItem", id, "spotPrice", vaultSharePrice2.toString());
      assert.fieldEquals("ProfitLossLineItem", id, "realizedPrice", "1018000000000000000");
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingAmountSpot", "-100000000");
    });

    test("incentive snapshot line items", () => {
      let id =
        account.toHexString() +
        ":" +
        vault.toHexString() +
        ":" +
        BigInt.fromI32(3).toString() +
        ":" +
        asset.toHexString();
      assert.fieldEquals("IncentiveSnapshot", id, "rewardToken", asset.toHexString());
      assert.fieldEquals(
        "IncentiveSnapshot",
        id,
        "totalClaimed",
        DEFAULT_PRECISION.times(BigInt.fromI32(5)).toString(),
      );
      assert.fieldEquals(
        "IncentiveSnapshot",
        id,
        "adjustedClaimed",
        // Adjusted down from 5e18 to 4.54 due to the prev / current balance
        "4545040946314831666",
      );
    });

    test("has vault share balance after exit position", () => {
      let id = account.toHexString() + ":" + vault.toHexString();
      assert.fieldEquals("Balance", id, "token", vault.toHexString());
      assert.fieldEquals("Balance", id, "account", account.toHexString());

      let snapshotId = id + ":" + BigInt.fromI32(3).toString();
      let snapshot = BalanceSnapshot.load(snapshotId);
      if (snapshot === null) assert.assertTrue(false, "snapshot is null");
      assert.assertTrue((snapshot as BalanceSnapshot).previousSnapshot !== null);
      let previousBalance = BigInt.fromI32(1099).times(DEFAULT_PRECISION);
      let currentBalance = BigInt.fromI32(999).times(DEFAULT_PRECISION);
      let vaultSharePrice2 = vaultSharePrice.plus(BigInt.fromI32(10).pow(16));

      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "previousBalance", previousBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedCostRealized", "1007200000");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "adjustedCostBasis", "916469");
      // Negative PnL includes loss from the initial deposit
      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentProfitAndLossAtSnapshot", "-8200000");

      // These both get adjusted downwards because of the redemption
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalInterestAccrualAtSnapshot", "9090081");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalVaultFeesAtSnapshot", "909008189262966333");
      assert.fieldEquals(
        "BalanceSnapshot",
        snapshotId,
        "_lastInterestAccumulator",
        vaultSharePrice2.times(USDC_PRECISION).div(DEFAULT_PRECISION).toString(),
      );
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_lastVaultFeeAccumulator", "999000000000000000");
    });

    test("has borrow share balance after assets repaid", () => {
      let borrowShareToken = vault.toHexString() + ":" + lendingRouter.toHexString();
      let id = account.toHexString() + ":" + borrowShareToken;
      assert.fieldEquals("Balance", id, "token", borrowShareToken);
      assert.fieldEquals("Balance", id, "account", account.toHexString());

      let snapshotId = id + ":" + BigInt.fromI32(3).toString();
      let snapshot = BalanceSnapshot.load(snapshotId);
      if (snapshot === null) assert.assertTrue(false, "snapshot is null");
      assert.assertTrue((snapshot as BalanceSnapshot).previousSnapshot !== null);
      let borrowSharesRepaid = BigInt.fromI32(90).times(BORROW_SHARE_PRECISION);
      let currentBalance = borrowSharesMinted.minus(borrowSharesRepaid);

      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "previousBalance", borrowSharesMinted.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedCostRealized", "817200000");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "adjustedCostBasis", "907999");

      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentProfitAndLossAtSnapshot", "9000000");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalInterestAccrualAtSnapshot", "9000000");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_lastInterestAccumulator", BigInt.zero().toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalVaultFeesAtSnapshot", BigInt.zero().toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_lastVaultFeeAccumulator", BigInt.zero().toString());
    });
  });

  describe("initiate withdraw request", () => {
    beforeAll(() => {
      listManager(vault, manager);

      let vaultShareBalance = BigInt.fromI32(999).times(DEFAULT_PRECISION);
      let initiateWithdrawRequestEvent = createInitiateWithdrawRequestEvent(
        manager,
        vault,
        account,
        vaultShareBalance,
        vaultShareBalance,
      );

      initiateWithdrawRequestEvent.block.number = BigInt.fromI32(4);
      initiateWithdrawRequestEvent.block.timestamp = initiateWithdrawRequestEvent.block.timestamp.plus(
        BigInt.fromI32(3600),
      );
      initiateWithdrawRequestEvent.transaction.hash = hash4;
      initiateWithdrawRequestEvent.transactionLogIndex = BigInt.fromI32(0);

      mockVaultSharePrice(vaultShareBalance, vaultSharePrice.plus(BigInt.fromI32(10).pow(16).times(BigInt.fromI32(2))));
      mockVaultFeePrice(BigInt.fromI32(20));

      createMockedFunction(vault, "convertSharesToYieldToken", "convertSharesToYieldToken(uint256):(uint256)")
        .withArgs([ethereum.Value.fromUnsignedBigInt(vaultShareBalance)])
        .returns([ethereum.Value.fromUnsignedBigInt(vaultShareBalance)]);

      handleInitiateWithdrawRequest(initiateWithdrawRequestEvent);
    });

    test("interest has been accrued and withdraw manager is set", () => {
      let id = account.toHexString() + ":" + vault.toHexString();
      assert.fieldEquals("Balance", id, "token", vault.toHexString());
      assert.fieldEquals("Balance", id, "account", account.toHexString());
      assert.fieldEquals(
        "Balance",
        id,
        "withdrawRequest",
        "[" + manager.toHexString() + ":" + vault.toHexString() + ":" + account.toHexString() + "]",
      );

      let snapshotId = id + ":" + BigInt.fromI32(4).toString();
      let snapshot = BalanceSnapshot.load(snapshotId);
      if (snapshot === null) assert.assertTrue(false, "snapshot is null");
      assert.assertTrue((snapshot as BalanceSnapshot).previousSnapshot !== null);
      let currentBalance = BigInt.fromI32(999).times(DEFAULT_PRECISION);
      let vaultSharePrice2 = vaultSharePrice.plus(BigInt.fromI32(10).pow(16).times(BigInt.fromI32(2)));

      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "previousBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedCostRealized", "1007200000");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "adjustedCostBasis", "1008208");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentProfitAndLossAtSnapshot", "1790000");

      // These both get adjusted downwards because of the redemption
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalInterestAccrualAtSnapshot", "19080081");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalVaultFeesAtSnapshot", "1908008189262966333");
      assert.fieldEquals(
        "BalanceSnapshot",
        snapshotId,
        "_lastInterestAccumulator",
        vaultSharePrice2.times(USDC_PRECISION).div(DEFAULT_PRECISION).toString(),
      );
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_lastVaultFeeAccumulator", "998000000000000000");
    });

    test("withdraw request pnl line item", () => {
      let pnlId =
        hash4.toHex() + ":" + BigInt.fromI32(1).toString() + ":" + account.toHexString() + ":" + vault.toHexString();
      let vaultShareBalance = BigInt.fromI32(999).times(DEFAULT_PRECISION);
      let yieldTokenAmount = vaultShareBalance;
      assert.fieldEquals("ProfitLossLineItem", pnlId, "lineItemType", "WithdrawRequest");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "token", vault.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "account", account.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingToken", yieldToken.toHexString());

      assert.fieldEquals("ProfitLossLineItem", pnlId, "tokenAmount", vaultShareBalance.toString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountRealized", yieldTokenAmount.toString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "spotPrice", "998000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "realizedPrice", "1000000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountSpot", vaultShareBalance.toString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "lineItemType", "WithdrawRequest");
    });
  });

  describe("liquidate position", () => {
    beforeAll(() => {
      let borrowSharesRepaid = BigInt.fromI32(90).times(BORROW_SHARE_PRECISION);
      let vaultSharesToLiquidator = BigInt.fromI32(99).times(DEFAULT_PRECISION);
      let liquidatePositionEvent = createLiquidatePositionEvent(
        liquidator,
        account,
        vault,
        borrowSharesRepaid,
        vaultSharesToLiquidator,
      );

      let tokenizedWithdraw = createWithdrawRequestTokenizedEvent(
        manager,
        account,
        liquidator,
        vault,
        BigInt.fromI32(1),
        vaultSharesToLiquidator,
      );
      tokenizedWithdraw.block.number = BigInt.fromI32(5);
      tokenizedWithdraw.block.timestamp = tokenizedWithdraw.block.timestamp.plus(BigInt.fromI32(3600));
      tokenizedWithdraw.transaction.hash = hash5;
      tokenizedWithdraw.transactionLogIndex = BigInt.fromI32(0);

      liquidatePositionEvent.block.number = BigInt.fromI32(5);
      liquidatePositionEvent.block.timestamp = liquidatePositionEvent.block.timestamp.plus(BigInt.fromI32(3600));
      liquidatePositionEvent.transaction.hash = hash5;

      let requestId = BigInt.fromI32(1);
      let vaultShareBalance = BigInt.fromI32(900).times(DEFAULT_PRECISION);
      createMockedFunction(vault, "convertSharesToYieldToken", "convertSharesToYieldToken(uint256):(uint256)")
        .withArgs([ethereum.Value.fromUnsignedBigInt(vaultSharesToLiquidator)])
        .returns([ethereum.Value.fromUnsignedBigInt(vaultSharesToLiquidator)]);
      createMockedFunction(
        manager,
        "getWithdrawRequest",
        "getWithdrawRequest(address,address):((uint256,uint120,uint120),(uint120,uint120,bool))",
      )
        .withArgs([ethereum.Value.fromAddress(vault), ethereum.Value.fromAddress(account)])
        .returns([
          ethereum.Value.fromTuple(
            changetype<ethereum.Tuple>([
              ethereum.Value.fromUnsignedBigInt(requestId),
              ethereum.Value.fromUnsignedBigInt(vaultShareBalance),
              ethereum.Value.fromUnsignedBigInt(vaultShareBalance),
            ]),
          ),
          ethereum.Value.fromTuple(
            changetype<ethereum.Tuple>([
              ethereum.Value.fromSignedBigInt(vaultShareBalance),
              ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
              ethereum.Value.fromBoolean(false),
            ]),
          ),
        ]);

      createMockedFunction(
        manager,
        "getWithdrawRequest",
        "getWithdrawRequest(address,address):((uint256,uint120,uint120),(uint120,uint120,bool))",
      )
        .withArgs([ethereum.Value.fromAddress(vault), ethereum.Value.fromAddress(liquidator)])
        .returns([
          ethereum.Value.fromTuple(
            changetype<ethereum.Tuple>([
              ethereum.Value.fromUnsignedBigInt(requestId),
              ethereum.Value.fromUnsignedBigInt(vaultSharesToLiquidator),
              ethereum.Value.fromUnsignedBigInt(vaultSharesToLiquidator),
            ]),
          ),
          ethereum.Value.fromTuple(
            changetype<ethereum.Tuple>([
              ethereum.Value.fromSignedBigInt(vaultShareBalance),
              ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
              ethereum.Value.fromBoolean(false),
            ]),
          ),
        ]);

      createMockedFunction(vault, "balanceOf", "balanceOf(address):(uint256)")
        .withArgs([ethereum.Value.fromAddress(liquidator)])
        .returns([ethereum.Value.fromUnsignedBigInt(vaultSharesToLiquidator)]);

      mockVaultSharePrice(vaultShareBalance, vaultSharePrice.plus(BigInt.fromI32(10).pow(16).times(BigInt.fromI32(5))));
      mockVaultFeePrice(BigInt.fromI32(30));
      mockBorrowSharePrice(
        // Do this twice to account for the previous exit
        borrowSharesMinted.minus(borrowSharesRepaid).minus(borrowSharesRepaid),
        borrowSharesRepaid,
        borrowSharesRepaid
          .times(USDC_PRECISION)
          .times(BigInt.fromI32(105))
          .div(BigInt.fromI32(100))
          .div(BORROW_SHARE_PRECISION),
      );

      // This event fires before liquidation in the stack
      handleWithdrawRequestTokenized(tokenizedWithdraw);
      handleLiquidatePosition(liquidatePositionEvent);
    });

    test("no vault share interest accrued since last snapshot", () => {
      let id = account.toHexString() + ":" + vault.toHexString();
      assert.fieldEquals("Balance", id, "token", vault.toHexString());
      assert.fieldEquals("Balance", id, "account", account.toHexString());
      assert.fieldEquals(
        "Balance",
        id,
        "withdrawRequest",
        "[" + manager.toHexString() + ":" + vault.toHexString() + ":" + account.toHexString() + "]",
      );

      let snapshotId = id + ":" + BigInt.fromI32(5).toString();
      let snapshot = BalanceSnapshot.load(snapshotId);
      if (snapshot === null) assert.assertTrue(false, "snapshot is null");
      assert.assertTrue((snapshot as BalanceSnapshot).previousSnapshot !== null);
      let previousBalance = BigInt.fromI32(999).times(DEFAULT_PRECISION);
      let currentBalance = BigInt.fromI32(900).times(DEFAULT_PRECISION);
      let vaultSharePrice2 = vaultSharePrice.plus(BigInt.fromI32(10).pow(16).times(BigInt.fromI32(2)));

      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "previousBalance", previousBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedCostRealized", "912700000");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "adjustedCostBasis", "913613");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentProfitAndLossAtSnapshot", "23300000");

      // These both get adjusted downwards because of the redemption
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalInterestAccrualAtSnapshot", "17189262");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalVaultFeesAtSnapshot", "1718926296633303002");

      // These two accumulators have not changed.
      assert.fieldEquals(
        "BalanceSnapshot",
        snapshotId,
        "_lastInterestAccumulator",
        vaultSharePrice2.times(USDC_PRECISION).div(DEFAULT_PRECISION).toString(),
      );
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_lastVaultFeeAccumulator", "998000000000000000");
    });

    test("vault share profit loss line item", () => {
      let vaultShare = vault.toHexString();
      let id =
        hash5.toHexString() + ":" + BigInt.fromI32(3).toString() + ":" + account.toHexString() + ":" + vaultShare;
      assert.fieldEquals("ProfitLossLineItem", id, "lineItemType", "LiquidatePosition");
      assert.fieldEquals("ProfitLossLineItem", id, "account", account.toHexString());
      assert.fieldEquals("ProfitLossLineItem", id, "token", vaultShare);
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingToken", asset.toHexString());

      assert.fieldEquals(
        "ProfitLossLineItem",
        id,
        "tokenAmount",
        DEFAULT_PRECISION.times(BigInt.fromI32(99)).neg().toString(),
      );
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingAmountRealized", "-94500000");
      assert.fieldEquals("ProfitLossLineItem", id, "realizedPrice", "954545454545454545");
      assert.fieldEquals("ProfitLossLineItem", id, "spotPrice", "1040000000000000000");
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingAmountSpot", "-102960000");
    });

    test("borrow share profit loss line item", () => {
      let borrowShareToken = vault.toHexString() + ":" + lendingRouter.toHexString();
      let id =
        hash5.toHexString() + ":" + BigInt.fromI32(3).toString() + ":" + account.toHexString() + ":" + borrowShareToken;
      assert.fieldEquals("ProfitLossLineItem", id, "lineItemType", "LiquidatePosition");
      assert.fieldEquals("ProfitLossLineItem", id, "account", account.toHexString());
      assert.fieldEquals("ProfitLossLineItem", id, "token", borrowShareToken);
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingToken", asset.toHexString());

      assert.fieldEquals(
        "ProfitLossLineItem",
        id,
        "tokenAmount",
        BORROW_SHARE_PRECISION.times(BigInt.fromI32(90)).neg().toString(),
      );
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingAmountRealized", "-94500000");
      assert.fieldEquals("ProfitLossLineItem", id, "realizedPrice", "1050000000000000000");
      assert.fieldEquals("ProfitLossLineItem", id, "spotPrice", "1050000000000000000");
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingAmountSpot", "-94500000");
    });

    test("has borrow share balance after liquidation", () => {
      let borrowShareToken = vault.toHexString() + ":" + lendingRouter.toHexString();
      let id = account.toHexString() + ":" + borrowShareToken;
      assert.fieldEquals("Balance", id, "token", borrowShareToken);
      assert.fieldEquals("Balance", id, "account", account.toHexString());

      let snapshotId = id + ":" + BigInt.fromI32(5).toString();
      let snapshot = BalanceSnapshot.load(snapshotId);
      if (snapshot === null) assert.assertTrue(false, "snapshot is null");
      assert.assertTrue((snapshot as BalanceSnapshot).previousSnapshot !== null);
      let borrowSharesRepaid = BigInt.fromI32(90).times(BORROW_SHARE_PRECISION);
      let currentBalance = borrowSharesMinted.minus(borrowSharesRepaid).minus(borrowSharesRepaid);

      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentBalance", currentBalance.toString());
      assert.fieldEquals(
        "BalanceSnapshot",
        snapshotId,
        "previousBalance",
        borrowSharesMinted.minus(borrowSharesRepaid).toString(),
      );
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedCostRealized", "722700000");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "adjustedCostBasis", "892222");

      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentProfitAndLossAtSnapshot", "33300000");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalInterestAccrualAtSnapshot", "33300000");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_lastInterestAccumulator", BigInt.zero().toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalVaultFeesAtSnapshot", BigInt.zero().toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_lastVaultFeeAccumulator", BigInt.zero().toString());
    });

    test("liquidator has vault share balance and pnl", () => {
      let vaultShare = vault.toHexString();
      let id =
        hash5.toHexString() + ":" + BigInt.fromI32(3).toString() + ":" + liquidator.toHexString() + ":" + vaultShare;
      assert.fieldEquals("ProfitLossLineItem", id, "lineItemType", "LiquidatePosition");
      assert.fieldEquals("ProfitLossLineItem", id, "account", liquidator.toHexString());
      assert.fieldEquals("ProfitLossLineItem", id, "token", vaultShare);
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingToken", asset.toHexString());

      assert.fieldEquals(
        "ProfitLossLineItem",
        id,
        "tokenAmount",
        DEFAULT_PRECISION.times(BigInt.fromI32(99)).toString(),
      );
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingAmountRealized", "94500000");
      assert.fieldEquals("ProfitLossLineItem", id, "realizedPrice", "954545454545454545");
      assert.fieldEquals("ProfitLossLineItem", id, "spotPrice", "1040000000000000000");
      assert.fieldEquals("ProfitLossLineItem", id, "underlyingAmountSpot", "102960000");
    });

    test("liquidator has no borrow share balance", () => {
      let borrowShareToken = vault.toHexString() + ":" + lendingRouter.toHexString();
      let id = liquidator.toHexString() + ":" + borrowShareToken;
      assert.notInStore("Balance", id);
    });

    test("liquidator withdraw request pnl line item", () => {
      let pnlId =
        hash5.toHex() + ":" + BigInt.fromI32(1).toString() + ":" + liquidator.toHexString() + ":" + vault.toHexString();
      let vaultShareBalance = BigInt.fromI32(99).times(DEFAULT_PRECISION);
      assert.fieldEquals("ProfitLossLineItem", pnlId, "lineItemType", "WithdrawRequest");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "token", vault.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "account", liquidator.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingToken", yieldToken.toHexString());

      assert.fieldEquals("ProfitLossLineItem", pnlId, "tokenAmount", vaultShareBalance.toString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountRealized", "99000000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "spotPrice", "997000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "realizedPrice", "1000000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountSpot", vaultShareBalance.toString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "lineItemType", "WithdrawRequest");
    });

    test("account withdraw request pnl line item", () => {
      let pnlId =
        hash5.toHex() + ":" + BigInt.fromI32(1).toString() + ":" + account.toHexString() + ":" + vault.toHexString();
      let vaultShareBalance = BigInt.fromI32(99).times(DEFAULT_PRECISION);
      assert.fieldEquals("ProfitLossLineItem", pnlId, "lineItemType", "WithdrawRequest");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "token", vault.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "account", account.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingToken", yieldToken.toHexString());

      assert.fieldEquals("ProfitLossLineItem", pnlId, "tokenAmount", vaultShareBalance.neg().toString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountRealized", "-99000000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "spotPrice", "997000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "realizedPrice", "1000000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountSpot", vaultShareBalance.neg().toString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "lineItemType", "WithdrawRequest");
    });
  });

  describe("finalize withdraw request", () => {
    beforeAll(() => {
      let withdrawRequestFinalizedEvent = createWithdrawRequestFinalizedEvent(
        manager,
        account,
        vault,
        BigInt.fromI32(1),
        BigInt.fromI32(100).times(USDC_PRECISION),
      );
      withdrawRequestFinalizedEvent.block.number = BigInt.fromI32(6);
      withdrawRequestFinalizedEvent.block.timestamp = withdrawRequestFinalizedEvent.block.timestamp.plus(
        BigInt.fromI32(3600),
      );
      withdrawRequestFinalizedEvent.transaction.hash = hash6;

      createMockedFunction(manager, "WITHDRAW_TOKEN", "WITHDRAW_TOKEN():(address)").returns([
        ethereum.Value.fromAddress(asset),
      ]);

      handleWithdrawRequestFinalized(withdrawRequestFinalizedEvent);
    });

    test("creates a withdraw request pnl line item", () => {
      let pnlId =
        hash6.toHex() + ":" + BigInt.fromI32(1).toString() + ":" + account.toHexString() + ":" + vault.toHexString();
      assert.fieldEquals("ProfitLossLineItem", pnlId, "lineItemType", "WithdrawRequestFinalized");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "token", yieldToken.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "account", account.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingToken", asset.toHexString());

      assert.fieldEquals("ProfitLossLineItem", pnlId, "tokenAmount", "900000000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountRealized", "100000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "realizedPrice", "111111111111111111");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "spotPrice", "0");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountSpot", "0");
    });

    test("creates a withdraw request pnl line item for liquidator", () => {
      let pnlId =
        hash6.toHex() + ":" + BigInt.fromI32(1).toString() + ":" + liquidator.toHexString() + ":" + vault.toHexString();
      assert.fieldEquals("ProfitLossLineItem", pnlId, "lineItemType", "WithdrawRequestFinalized");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "token", yieldToken.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "account", liquidator.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingToken", asset.toHexString());

      assert.fieldEquals(
        "ProfitLossLineItem",
        pnlId,
        "tokenAmount",
        DEFAULT_PRECISION.times(BigInt.fromI32(99)).toString(),
      );
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountRealized", "11000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "realizedPrice", "111111111111111111");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "spotPrice", "0");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountSpot", "0");
    });

    test("no interest accrued since last snapshot", () => {
      let id = account.toHexString() + ":" + vault.toHexString();
      assert.fieldEquals("Balance", id, "token", vault.toHexString());
      assert.fieldEquals("Balance", id, "account", account.toHexString());
      assert.fieldEquals(
        "Balance",
        id,
        "withdrawRequest",
        "[" + manager.toHexString() + ":" + vault.toHexString() + ":" + account.toHexString() + "]",
      );

      let snapshotId = id + ":" + BigInt.fromI32(6).toString();
      let snapshot = BalanceSnapshot.load(snapshotId);
      if (snapshot === null) assert.assertTrue(false, "snapshot is null");
      assert.assertTrue((snapshot as BalanceSnapshot).previousSnapshot !== null);
      let currentBalance = BigInt.fromI32(900).times(DEFAULT_PRECISION);
      let vaultSharePrice2 = vaultSharePrice.plus(BigInt.fromI32(10).pow(16).times(BigInt.fromI32(2)));

      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "previousBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedBalance", currentBalance.toString());
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedCostRealized", "912700000");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "adjustedCostBasis", "1014111");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentProfitAndLossAtSnapshot", "23300000");

      // These both get adjusted downwards because of the redemption
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalInterestAccrualAtSnapshot", "17189262");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "totalVaultFeesAtSnapshot", "1718926296633303002");

      // These two accumulators have not changed.
      assert.fieldEquals(
        "BalanceSnapshot",
        snapshotId,
        "_lastInterestAccumulator",
        vaultSharePrice2.times(USDC_PRECISION).div(DEFAULT_PRECISION).toString(),
      );
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_lastVaultFeeAccumulator", "998000000000000000");
    });
  });

  describe("full exit position withdraw request", () => {
    beforeAll(() => {
      let vaultSharesRemaining = DEFAULT_PRECISION.times(BigInt.fromI32(900));
      let borrowSharesRemaining = BORROW_SHARE_PRECISION.times(BigInt.fromI32(720));
      let exitPositionEvent = createExitPositionEvent(
        account,
        vault,
        borrowSharesRemaining,
        vaultSharesRemaining,
        BigInt.fromI32(100).times(USDC_PRECISION),
      );
      exitPositionEvent.block.number = BigInt.fromI32(7);
      exitPositionEvent.block.timestamp = exitPositionEvent.block.timestamp.plus(BigInt.fromI32(3600));
      exitPositionEvent.transaction.hash = hash7;
      exitPositionEvent.transactionLogIndex = BigInt.fromI32(1);

      mockVaultSharePrice(BigInt.zero(), vaultSharePrice);
      mockBorrowSharePrice(
        BigInt.zero(),
        borrowSharesRemaining,
        borrowSharesRemaining
          .times(USDC_PRECISION)
          .times(BigInt.fromI32(105))
          .div(BigInt.fromI32(100))
          .div(BORROW_SHARE_PRECISION),
      );

      handleExitPosition(exitPositionEvent);
    });

    test("creates a vault share pnl item", () => {
      let pnlId =
        hash7.toHex() + ":" + BigInt.fromI32(3).toString() + ":" + account.toHexString() + ":" + vault.toHexString();
      assert.fieldEquals("ProfitLossLineItem", pnlId, "lineItemType", "ExitPosition");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "token", vault.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "account", account.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingToken", asset.toHexString());

      assert.fieldEquals("ProfitLossLineItem", pnlId, "tokenAmount", "-900000000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountRealized", "-856000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "spotPrice", "990000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "realizedPrice", "951111111111111111");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountSpot", "-891000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "lineItemType", "ExitPosition");
    });

    test("creates a borrow share pnl item", () => {
      let borrowShareToken = vault.toHexString() + ":" + lendingRouter.toHexString();
      let pnlId =
        hash7.toHex() + ":" + BigInt.fromI32(3).toString() + ":" + account.toHexString() + ":" + borrowShareToken;
      assert.fieldEquals("ProfitLossLineItem", pnlId, "lineItemType", "ExitPosition");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "token", borrowShareToken);
      assert.fieldEquals("ProfitLossLineItem", pnlId, "account", account.toHexString());
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingToken", asset.toHexString());

      assert.fieldEquals("ProfitLossLineItem", pnlId, "tokenAmount", "-720000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountRealized", "-756000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "spotPrice", "1050000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "realizedPrice", "1050000000000000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "underlyingAmountSpot", "-756000000");
      assert.fieldEquals("ProfitLossLineItem", pnlId, "lineItemType", "ExitPosition");
    });

    test("updates vault share balance snapshot", () => {
      let id = account.toHexString() + ":" + vault.toHexString();
      let snapshotId = id + ":" + BigInt.fromI32(7).toString();
      let snapshot = BalanceSnapshot.load(snapshotId);
      if (snapshot === null) assert.assertTrue(false, "snapshot is null");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedBalance", "0");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentBalance", "0");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "adjustedCostBasis", "0");
    });

    test("updates borrow share balance snapshot", () => {
      let id = account.toHexString() + ":" + vault.toHexString();
      let snapshotId = id + ":" + BigInt.fromI32(7).toString();
      let snapshot = BalanceSnapshot.load(snapshotId);
      if (snapshot === null) assert.assertTrue(false, "snapshot is null");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "_accumulatedBalance", "0");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "currentBalance", "0");
      assert.fieldEquals("BalanceSnapshot", snapshotId, "adjustedCostBasis", "0");
    });
  });

  afterAll(() => {
    clearStore();
  });
});

describe("enter pendle pt position interest accrual", () => {
  beforeAll(() => {
    createVault(vault);
    baseMockFunctions("PendlePT");
    createMockedFunction(yieldToken, "expiry", "expiry():(uint256)").returns([
      ethereum.Value.fromUnsignedBigInt(SECONDS_IN_YEAR),
    ]);

    createMockedFunction(vault, "feeRate", "feeRate():(uint256)").returns([
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(10).pow(14)),
    ]);

    createMockedFunction(accountingAsset, "name", "name():(string)").returns([
      ethereum.Value.fromString("Accounting Asset"),
    ]);
    createMockedFunction(accountingAsset, "symbol", "symbol():(string)").returns([ethereum.Value.fromString("AA")]);
    createMockedFunction(accountingAsset, "decimals", "decimals():(uint8)").returns([
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(6)),
    ]);
    createMockedFunction(vault, "convertSharesToYieldToken", "convertSharesToYieldToken(uint256):(uint256)")
      .withArgs([ethereum.Value.fromUnsignedBigInt(vaultSharesMinted)])
      .returns([ethereum.Value.fromUnsignedBigInt(vaultSharesMinted)]);

    let asset = new Token(accountingAsset.toHexString());
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
    asset.tokenAddress = Bytes.fromHexString(accountingAsset.toHexString());
    asset.save();

    mockVaultSharePrice(vaultSharesMinted, vaultSharePrice);
    mockBorrowSharePrice(
      borrowSharesMinted,
      borrowSharesMinted,
      borrowSharesMinted
        .times(USDC_PRECISION)
        .times(BigInt.fromI32(101))
        .div(BigInt.fromI32(100))
        .div(BORROW_SHARE_PRECISION),
    );
    mockVaultFeePrice(BigInt.fromI32(0));

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
      Bytes.fromHexString(padHexString(accountingAsset.toHexString())),
      Bytes.fromHexString(padHexString(yieldToken.toHexString())),
    ];
    tradeExecutedLog.data = ethereum.encode(
      ethereum.Value.fromTuple(
        changetype<ethereum.Tuple>([
          ethereum.Value.fromUnsignedBigInt(USDC_PRECISION.times(BigInt.fromI32(998))),
          ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION.times(BigInt.fromI32(1000))),
        ]),
      ),
    )!;

    enterPositionEvent.receipt!.logs = [tradeExecutedLog];

    handleEnterPosition(enterPositionEvent);
  });

  test("interest accrual is correct", () => {
    let id = account.toHexString() + ":" + vault.toHexString();
    let snapshotId = id + ":" + BigInt.fromI32(1).toString();
    let snapshot = BalanceSnapshot.load(snapshotId);
    if (snapshot === null) assert.assertTrue(false, "snapshot is null");
    assert.fieldEquals("BalanceSnapshot", snapshotId, "totalInterestAccrualAtSnapshot", "0");
  });
});
