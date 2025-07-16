import { describe, test, beforeAll, createMockedFunction, newMockEvent, logStore, newLog } from "matchstick-as";
import { Address, ethereum, BigInt, ByteArray, crypto, Bytes } from "@graphprotocol/graph-ts";
import { createVault } from "./withdraw-request-manager.test";
import { DEFAULT_PRECISION } from "../src/constants";
import { EnterPosition } from "../generated/templates/LendingRouter/ILendingRouter";
import { handleEnterPosition } from "../src/lending-router";

let vault = Address.fromString("0x0000000000000000000000000000000000000001")
let lendingRouter = Address.fromString("0x00000000000000000000000000000000000000AA")
let account = Address.fromString("0x0000000000000000000000000000000000000AAA")

function createEnterPositionEvent(
  user: Address,
  vault: Address,
  depositAssets: BigInt,
  borrowShares: BigInt,
  vaultSharesReceived: BigInt,
  wasMigrated: boolean,
): EnterPosition {
  let enterPositionEvent = changetype<EnterPosition>(newMockEvent())

  enterPositionEvent.parameters = new Array()

  enterPositionEvent.parameters.push(
    new ethereum.EventParam("user", ethereum.Value.fromAddress(user))
  )

  enterPositionEvent.parameters.push(
    new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault))
  )

  enterPositionEvent.parameters.push(
    new ethereum.EventParam("depositAssets", ethereum.Value.fromUnsignedBigInt(depositAssets))
  )

  enterPositionEvent.parameters.push(
    new ethereum.EventParam("borrowShares", ethereum.Value.fromUnsignedBigInt(borrowShares))
  )

  enterPositionEvent.parameters.push(
    new ethereum.EventParam("vaultSharesReceived", ethereum.Value.fromUnsignedBigInt(vaultSharesReceived))
  )

  enterPositionEvent.parameters.push(
    new ethereum.EventParam("wasMigrated", ethereum.Value.fromBoolean(wasMigrated))
  )

  enterPositionEvent.address = lendingRouter

  return enterPositionEvent
}

describe("enter position with borrow shares", () => {
  beforeAll(() => {
    createVault(vault)

    createMockedFunction(
      vault,
      "asset",
      "asset():(address)"
    ).returns([
      ethereum.Value.fromAddress(Address.fromString("0x00000000000000000000000000000000000000ff"))
    ])

    createMockedFunction(
      vault,
      "accountingAsset",
      "accountingAsset():(address)"
    ).returns([
      ethereum.Value.fromAddress(Address.fromString("0x00000000000000000000000000000000000000ff"))
    ])

    createMockedFunction(
      vault,
      "yieldToken",
      "yieldToken():(address)"
    ).returns([
      ethereum.Value.fromAddress(Address.fromString("0x00000000000000000000000000000000000000ff"))
    ])

    createMockedFunction(
      vault,
      "price",
      "price(address):(uint256)"
    ).withArgs([
      ethereum.Value.fromAddress(account)
    ]).returns([
      ethereum.Value.fromUnsignedBigInt(
        DEFAULT_PRECISION.times(DEFAULT_PRECISION).times(BigInt.fromI32(99)).div(BigInt.fromI32(100))
      )
    ])

    createMockedFunction(
      vault,
      "convertToAssets",
      "convertToAssets(uint256):(uint256)"
    ).withArgs([
      ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION)
    ]).returns([
      ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION
        .times(BigInt.fromI32(99)).div(BigInt.fromI32(100))
      )
    ])

    createMockedFunction(
      vault,
      "convertSharesToYieldToken",
      "convertSharesToYieldToken(uint256):(uint256)"
    ).withArgs([
      ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION)
    ]).returns([
      ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION
        .times(BigInt.fromI32(95)).div(BigInt.fromI32(100)))
    ])

    createMockedFunction(
      vault,
      "strategy",
      "strategy():(string)"
    ).returns([
      ethereum.Value.fromString("CurveConvex2Token")
    ])

    createMockedFunction(
      vault,
      "convertYieldTokenToShares",
      "convertYieldTokenToShares(uint256):(uint256)"
    ).withArgs([
      ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION)
    ]).returns([
      ethereum.Value.fromUnsignedBigInt(
        DEFAULT_PRECISION.times(BigInt.fromI32(1000)).div(BigInt.fromI32(95))
      )
    ])

    createMockedFunction(
      lendingRouter,
      "balanceOfCollateral",
      "balanceOfCollateral(address,address):(uint256)"
    ).withArgs([
      ethereum.Value.fromAddress(account),
      ethereum.Value.fromAddress(vault)
    ]).returns([
      ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION.times(BigInt.fromI32(1000)))
    ])

    createMockedFunction(
      lendingRouter,
      "balanceOfBorrowShares",
      "balanceOfBorrowShares(address,address):(uint256)"
    ).withArgs([
      ethereum.Value.fromAddress(account),
      ethereum.Value.fromAddress(vault)
    ]).returns([
      ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION.times(BigInt.fromI32(1000)))
    ])

    createMockedFunction(
      lendingRouter,
      "name",
      "name():(string)"
    ).returns([
      ethereum.Value.fromString("Morpho")
    ])

    createMockedFunction(
      lendingRouter,
      "borrowShareDecimals",
      "borrowShareDecimals():(uint8)"
    ).returns([
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(18))
    ])

    createMockedFunction(
      lendingRouter,
      "convertBorrowSharesToAssets",
      "convertBorrowSharesToAssets(address,uint256):(uint256)"
    ).withArgs([
      ethereum.Value.fromAddress(vault),
      ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION.times(BigInt.fromI32(1000)))
    ]).returns([
      ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION.times(BigInt.fromI32(1000)))
    ])

    let enterPositionEvent = createEnterPositionEvent(
      account,
      vault,
      DEFAULT_PRECISION.times(BigInt.fromI32(1000)),
      DEFAULT_PRECISION.times(BigInt.fromI32(1000)),
      DEFAULT_PRECISION.times(BigInt.fromI32(1000)),
      false
    )

    // Add TradeExecuted log
    let tradeExecutedLog = newLog()
    tradeExecutedLog.address = vault
    tradeExecutedLog.topics = [
      Bytes.fromByteArray(crypto.keccak256(ByteArray.fromUTF8("TradeExecuted(address,address,uint256,uint256)"))),
      Bytes.fromHexString("0x00000000000000000000000000000000000000ff"),
      Bytes.fromHexString("0x00000000000000000000000000000000000000ff"),
    ]
    tradeExecutedLog.data = Bytes.fromByteArray(ByteArray.fromBigInt(DEFAULT_PRECISION).concat(
      ByteArray.fromBigInt(DEFAULT_PRECISION)
    ));

    let incentiveTransferLog = newLog()
    incentiveTransferLog.address = vault
    incentiveTransferLog.topics = [
      Bytes.fromByteArray(crypto.keccak256(ByteArray.fromUTF8("VaultRewardTransfer(address,address,uint256)"))),
      Bytes.fromHexString("0x00000000000000000000000000000000000000ff"),
      Bytes.fromHexString(account.toHexString())
    ]
    incentiveTransferLog.data = Bytes.fromByteArray(ByteArray.fromBigInt(DEFAULT_PRECISION));

    enterPositionEvent.receipt!.logs = [tradeExecutedLog, incentiveTransferLog]

    handleEnterPosition(enterPositionEvent)
  })

  test("has profit loss line item", () => {
    logStore()
  });
  test("has vault share balance", () => {
  });
  test("has borrow share balance", () => {
  });
  test("has trade execution line items", () => {
  });
  test("incentive snapshot line items", () => {
  });
});

describe("enter position with no borrow shares", () => {
});

describe("exit position with no assets repaid", () => {
});

describe("exit position with assets repaid", () => {
});

describe("initiate withdraw request", () => {
});


describe("liquidate position", () => {
});