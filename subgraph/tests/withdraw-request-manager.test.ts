import { assert, describe, test, afterAll, beforeEach, clearStore, newMockEvent, afterEach, logStore, createMockedFunction } from "matchstick-as/assembly/index";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import { ApprovedVault, InitiateWithdrawRequest, WithdrawRequestTokenized } from "../generated/templates/WithdrawRequestManager/IWithdrawRequestManager";
import { handleApprovedVault, handleInitiateWithdrawRequest, handleWithdrawRequestTokenized } from "../src/withdraw-request-manager";
import { Token, TokenizedWithdrawRequest, Vault, WithdrawRequest } from "../generated/schema";

function createApprovedVaultEvent(
  manager: Address,
  vault: Address,
  isApproved: boolean
): ApprovedVault {
  let approvedVaultEvent = changetype<ApprovedVault>(newMockEvent())

  approvedVaultEvent.parameters = new Array()

  approvedVaultEvent.parameters.push(
    new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault))
  )
  approvedVaultEvent.parameters.push(
    new ethereum.EventParam("isApproved", ethereum.Value.fromBoolean(isApproved))
  )

  approvedVaultEvent.address = manager;

  return approvedVaultEvent
}

function createInitiateWithdrawRequestEvent(
  manager: Address,
  vault: Address,
  account: Address,
  yieldTokenAmount: BigInt,
  sharesAmount: BigInt
): InitiateWithdrawRequest {
  let initiateWithdrawRequestEvent = changetype<InitiateWithdrawRequest>(newMockEvent())

  initiateWithdrawRequestEvent.parameters = new Array()

  initiateWithdrawRequestEvent.parameters.push(
    new ethereum.EventParam("account", ethereum.Value.fromAddress(account))
  )
  initiateWithdrawRequestEvent.parameters.push(
    new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault))
  )
  initiateWithdrawRequestEvent.parameters.push(
    new ethereum.EventParam("yieldTokenAmount", ethereum.Value.fromUnsignedBigInt(yieldTokenAmount))
  )
  initiateWithdrawRequestEvent.parameters.push( 
    new ethereum.EventParam("sharesAmount", ethereum.Value.fromUnsignedBigInt(sharesAmount))
  )
  initiateWithdrawRequestEvent.parameters.push(
    new ethereum.EventParam("requestId", ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1)))
  )

  initiateWithdrawRequestEvent.address = manager

  return initiateWithdrawRequestEvent
}

export function createVault(vault: Address): Vault {
  let v = new Vault(vault.toHexString())
  v.firstUpdateBlockNumber = BigInt.fromI32(1)
  v.firstUpdateTimestamp = 1
  v.firstUpdateTransactionHash = Bytes.fromI32(1)
  v.lastUpdateBlockNumber = BigInt.fromI32(1)
  v.lastUpdateTimestamp = 1
  v.lastUpdateTransactionHash = Bytes.fromI32(1)
  v.isWhitelisted = true
  v.asset = "0x00000000000000000000000000000000000000ff"
  v.yieldToken = "0x00000000000000000000000000000000000000ee"
  v.vaultToken = vault.toHexString()
  v.feeRate = BigInt.fromI32(1000)
  v.withdrawRequestManagers = []
  v.save()

  let vaultShare = new Token(vault.toHexString())
  vaultShare.firstUpdateBlockNumber = BigInt.fromI32(1)
  vaultShare.firstUpdateTimestamp = 1
  vaultShare.firstUpdateTransactionHash = Bytes.fromI32(1)
  vaultShare.lastUpdateBlockNumber = BigInt.fromI32(1)
  vaultShare.lastUpdateTimestamp = 1
  vaultShare.lastUpdateTransactionHash = Bytes.fromI32(1)
  vaultShare.tokenType = "VaultShare"
  vaultShare.tokenInterface = "ERC20"
  vaultShare.underlying = v.asset
  vaultShare.name = "Vault Share"
  vaultShare.symbol = "VSH"
  vaultShare.decimals = 18
  vaultShare.precision = BigInt.fromI32(10).pow(18)
  vaultShare.vaultAddress = vault
  vaultShare.tokenAddress = vault
  vaultShare.save()

  let asset = new Token(v.asset)
  asset.firstUpdateBlockNumber = BigInt.fromI32(1)
  asset.firstUpdateTimestamp = 1
  asset.firstUpdateTransactionHash = Bytes.fromI32(1)
  asset.lastUpdateBlockNumber = BigInt.fromI32(1)
  asset.lastUpdateTimestamp = 1
  asset.lastUpdateTransactionHash = Bytes.fromI32(1)
  asset.tokenType = "Underlying"
  asset.tokenInterface = "ERC20"
  asset.name = "Asset"
  asset.symbol = "ASSET"
  asset.decimals = 18
  asset.precision = BigInt.fromI32(10).pow(18)
  asset.tokenAddress = Bytes.fromHexString(v.asset)
  asset.save()

  return v
}

function listManager(vault: Address, manager: Address): void {
  let isApproved = true
  let newApprovedVaultEvent = createApprovedVaultEvent(manager, vault, isApproved)
  handleApprovedVault(newApprovedVaultEvent)
}

function createWithdrawRequestTokenizedEvent(
  manager: Address,
  from: Address,
  to: Address,
  vault: Address,
  requestId: BigInt,
  sharesAmount: BigInt
): WithdrawRequestTokenized {
  let withdrawRequestTokenizedEvent = changetype<WithdrawRequestTokenized>(newMockEvent())

  withdrawRequestTokenizedEvent.parameters = new Array()

  withdrawRequestTokenizedEvent.parameters.push(
    new ethereum.EventParam("from", ethereum.Value.fromAddress(from))
  )
  withdrawRequestTokenizedEvent.parameters.push(
    new ethereum.EventParam("to", ethereum.Value.fromAddress(to))
  )
  withdrawRequestTokenizedEvent.parameters.push(
    new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault))
  )
  withdrawRequestTokenizedEvent.parameters.push(
    new ethereum.EventParam("requestId", ethereum.Value.fromUnsignedBigInt(requestId))
  )
  withdrawRequestTokenizedEvent.parameters.push(
    new ethereum.EventParam("sharesAmount", ethereum.Value.fromUnsignedBigInt(sharesAmount))
  )

  withdrawRequestTokenizedEvent.address = manager

  return withdrawRequestTokenizedEvent
}

describe("Approve withdraw request manager lists on vault", () => {
  beforeEach(() => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let manager = Address.fromString("0x0000000000000000000000000000000000000002")
    createVault(vault)
    listManager(vault, manager)
  })

  test("listing multiple withdraw request managers", () => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let manager = Address.fromString("0x0000000000000000000000000000000000000003")

    assert.fieldEquals("Vault",
      vault.toHexString(),
      "withdrawRequestManagers",
      "[0x0000000000000000000000000000000000000002]"
    )

    listManager(vault, manager)
    assert.fieldEquals("Vault",
      vault.toHexString(),
      "withdrawRequestManagers",
      "[0x0000000000000000000000000000000000000002, 0x0000000000000000000000000000000000000003]"
    )
  })

  test("removing a withdraw request manager", () => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let manager = Address.fromString("0x0000000000000000000000000000000000000002")
    let isApproved = false
    let newApprovedVaultEvent = createApprovedVaultEvent(manager, vault, isApproved)
    handleApprovedVault(newApprovedVaultEvent)

    assert.fieldEquals("Vault",
      vault.toHexString(),
      "withdrawRequestManagers",
      "[]"
    )
  })

  afterEach(() => {
    clearStore()
  })
})

describe("Initiate withdraw request", () => {
  beforeEach(() => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let manager = Address.fromString("0x0000000000000000000000000000000000000002")
    createVault(vault)
    listManager(vault, manager)

    let account = Address.fromString("0x0000000000000000000000000000000000000003")
    let yieldTokenAmount = BigInt.fromI32(1000)
    let sharesAmount = BigInt.fromI32(1000)
    let newInitiateWithdrawRequestEvent = createInitiateWithdrawRequestEvent(
      manager, vault, account, yieldTokenAmount, sharesAmount
    )
    handleInitiateWithdrawRequest(newInitiateWithdrawRequestEvent)
  })

  test("initiate withdraw request", () => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let manager = Address.fromString("0x0000000000000000000000000000000000000002")
    let account = Address.fromString("0x0000000000000000000000000000000000000003")
    let id = manager.toHexString() + ":" + vault.toHexString() + ":" + account.toHexString()

    assert.fieldEquals("WithdrawRequest",
      id,
      "requestId",
      "1"
    )
    assert.fieldEquals("WithdrawRequest",
      id,
      "yieldTokenAmount",
      "1000"
    )
    assert.fieldEquals("WithdrawRequest",
      id,
      "sharesAmount",
      "1000"
    )
    assert.fieldEquals("WithdrawRequest",
      id,
      "balance",
      "0x0000000000000000000000000000000000000003:0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals("WithdrawRequest",
      id,
      "account",
      "0x0000000000000000000000000000000000000003"
    )
    assert.fieldEquals("WithdrawRequest",
      id,
      "vault",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals("WithdrawRequest",
      id,
      "withdrawRequestManager",
      "0x0000000000000000000000000000000000000002"
    )

    // TODO: test interest and fee accrual set to zero
  })

  test("tokenized withdraw request, split from and to", () => {
    let from = Address.fromString("0x0000000000000000000000000000000000000003")
    let to = Address.fromString("0x0000000000000000000000000000000000000004")
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let manager = Address.fromString("0x0000000000000000000000000000000000000002")
    let sharesAmount = BigInt.fromI32(500)
    let requestId = BigInt.fromI32(1)
    let newWithdrawRequestTokenizedEvent = createWithdrawRequestTokenizedEvent(
      manager, from, to, vault, requestId, sharesAmount
    )
    createMockedFunction(manager, "getWithdrawRequest", "getWithdrawRequest(address,address):((uint256,uint120,uint120),(uint120,uint120,bool))")
      .withArgs([
        ethereum.Value.fromAddress(vault),
        ethereum.Value.fromAddress(from)
      ])
      .returns(
        [
          ethereum.Value.fromTuple(changetype<ethereum.Tuple>([
            ethereum.Value.fromUnsignedBigInt(requestId),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromUnsignedBigInt(sharesAmount)
          ])),
          ethereum.Value.fromTuple(changetype<ethereum.Tuple>([
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromBoolean(false)
          ]))
        ]
      )

    createMockedFunction(manager, "getWithdrawRequest", "getWithdrawRequest(address,address):((uint256,uint120,uint120),(uint120,uint120,bool))")
      .withArgs([
        ethereum.Value.fromAddress(vault),
        ethereum.Value.fromAddress(to)
      ])
      .returns(
        [
          ethereum.Value.fromTuple(changetype<ethereum.Tuple>([
            ethereum.Value.fromUnsignedBigInt(requestId),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromUnsignedBigInt(sharesAmount)
          ])),
          ethereum.Value.fromTuple(changetype<ethereum.Tuple>([
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromBoolean(false)
          ]))
        ]
      )

    handleWithdrawRequestTokenized(newWithdrawRequestTokenizedEvent)
    let id = manager.toHexString() + ":" + requestId.toString()

    assert.fieldEquals("TokenizedWithdrawRequest",
      id,
      "withdrawRequestManager",
      "0x0000000000000000000000000000000000000002"
    )
    assert.fieldEquals("TokenizedWithdrawRequest",
      id,
      "totalYieldTokenAmount",
      "1000"
    )
    assert.fieldEquals("TokenizedWithdrawRequest",
      id,
      "totalWithdraw",
      "0"
    )
    assert.fieldEquals("TokenizedWithdrawRequest",
      id,
      "finalized",
      "false"
    )

    let id1 = manager.toHexString() + ":" + vault.toHexString() + ":" + from.toHexString()
    assert.fieldEquals("WithdrawRequest",
      id1,
      "tokenizedWithdrawRequest",
      id
    )
    assert.fieldEquals("WithdrawRequest",
      id1,
      "withdrawRequestManager",
      "0x0000000000000000000000000000000000000002"
    )
    assert.fieldEquals("WithdrawRequest",
      id1,
      "vault",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals("WithdrawRequest",
      id1,
      "account",
      "0x0000000000000000000000000000000000000003"
    )
    assert.fieldEquals("WithdrawRequest",
      id1,
      "sharesAmount",
      "500"
    )


    let id2 = manager.toHexString() + ":" + vault.toHexString() + ":" + to.toHexString()
    assert.fieldEquals("WithdrawRequest",
      id2,
      "tokenizedWithdrawRequest",
      id
    )
    assert.fieldEquals("WithdrawRequest",
      id2,
      "withdrawRequestManager",
      "0x0000000000000000000000000000000000000002"
    )
    assert.fieldEquals("WithdrawRequest",
      id2,
      "vault",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals("WithdrawRequest",
      id2,
      "account",
      "0x0000000000000000000000000000000000000004"
    )
    assert.fieldEquals("WithdrawRequest",
      id2,
      "sharesAmount",
      "500"
    )

    // TODO: test interest and fee accrual set to zero
  })

  test("tokenized withdraw request, split from and to, existing to", () => {
    let from = Address.fromString("0x0000000000000000000000000000000000000003")
    let to = Address.fromString("0x0000000000000000000000000000000000000004")
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let manager = Address.fromString("0x0000000000000000000000000000000000000002")
    let sharesAmount = BigInt.fromI32(500)
    let requestId = BigInt.fromI32(1)
    let newWithdrawRequestTokenizedEvent = createWithdrawRequestTokenizedEvent(
      manager, from, to, vault, requestId, sharesAmount
    )

    let twr = new TokenizedWithdrawRequest(manager.toHexString() + ":" + requestId.toString())
    twr.lastUpdateBlockNumber = BigInt.fromI32(1)
    twr.lastUpdateTimestamp = 1
    twr.lastUpdateTransactionHash = Bytes.fromI32(1)
    twr.withdrawRequestManager = manager.toHexString()
    twr.totalYieldTokenAmount = BigInt.fromI32(1000)
    twr.totalWithdraw = BigInt.fromI32(0)
    twr.finalized = false
    twr.save()

    let w = new WithdrawRequest(manager.toHexString() + ":" + vault.toHexString() + ":" + to.toHexString())
    w.tokenizedWithdrawRequest = twr.id
    w.withdrawRequestManager = manager.toHexString()
    w.vault = vault.toHexString()
    w.account = to.toHexString()
    w.requestId = requestId
    w.balance = vault.toHexString() + ":" + to.toHexString()
    w.sharesAmount = sharesAmount
    w.yieldTokenAmount = BigInt.fromI32(1000)
    w.lastUpdateBlockNumber = BigInt.fromI32(1)
    w.lastUpdateTimestamp = 1
    w.lastUpdateTransactionHash = Bytes.fromI32(1)
    w.save()

    createMockedFunction(manager, "getWithdrawRequest", "getWithdrawRequest(address,address):((uint256,uint120,uint120),(uint120,uint120,bool))")
      .withArgs([
        ethereum.Value.fromAddress(vault),
        ethereum.Value.fromAddress(from)
      ])
      .returns(
        [
          ethereum.Value.fromTuple(changetype<ethereum.Tuple>([
            ethereum.Value.fromUnsignedBigInt(requestId),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromUnsignedBigInt(sharesAmount)
          ])),
          ethereum.Value.fromTuple(changetype<ethereum.Tuple>([
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromBoolean(false)
          ]))
        ]
      )

    createMockedFunction(manager, "getWithdrawRequest", "getWithdrawRequest(address,address):((uint256,uint120,uint120),(uint120,uint120,bool))")
      .withArgs([
        ethereum.Value.fromAddress(vault),
        ethereum.Value.fromAddress(to)
      ])
      .returns(
        [
          ethereum.Value.fromTuple(changetype<ethereum.Tuple>([
            ethereum.Value.fromUnsignedBigInt(requestId),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromUnsignedBigInt(sharesAmount)
          ])),
          ethereum.Value.fromTuple(changetype<ethereum.Tuple>([
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromBoolean(false)
          ]))
        ]
      )

    handleWithdrawRequestTokenized(newWithdrawRequestTokenizedEvent)
    let id = manager.toHexString() + ":" + requestId.toString()

    assert.fieldEquals("TokenizedWithdrawRequest",
      id,
      "withdrawRequestManager",
      "0x0000000000000000000000000000000000000002"
    )
    assert.fieldEquals("TokenizedWithdrawRequest",
      id,
      "totalYieldTokenAmount",
      "1000"
    )
    assert.fieldEquals("TokenizedWithdrawRequest",
      id,
      "totalWithdraw",
      "0"
    )
    assert.fieldEquals("TokenizedWithdrawRequest",
      id,
      "finalized",
      "false"
    )

    let id1 = manager.toHexString() + ":" + vault.toHexString() + ":" + from.toHexString()
    assert.fieldEquals("WithdrawRequest",
      id1,
      "tokenizedWithdrawRequest",
      id
    )
    assert.fieldEquals("WithdrawRequest",
      id1,
      "withdrawRequestManager",
      "0x0000000000000000000000000000000000000002"
    )
    assert.fieldEquals("WithdrawRequest",
      id1,
      "vault",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals("WithdrawRequest",
      id1,
      "account",
      "0x0000000000000000000000000000000000000003"
    )
    assert.fieldEquals("WithdrawRequest",
      id1,
      "sharesAmount",
      "500"
    )


    let id2 = manager.toHexString() + ":" + vault.toHexString() + ":" + to.toHexString()
    assert.fieldEquals("WithdrawRequest",
      id2,
      "tokenizedWithdrawRequest",
      id
    )
    assert.fieldEquals("WithdrawRequest",
      id2,
      "withdrawRequestManager",
      "0x0000000000000000000000000000000000000002"
    )
    assert.fieldEquals("WithdrawRequest",
      id2,
      "vault",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals("WithdrawRequest",
      id2,
      "account",
      "0x0000000000000000000000000000000000000004"
    )
    assert.fieldEquals("WithdrawRequest",
      id2,
      "sharesAmount",
      "500"
    )

  })

  test("tokenized withdraw request, delete from", () => {
    let from = Address.fromString("0x0000000000000000000000000000000000000003")
    let to = Address.fromString("0x0000000000000000000000000000000000000004")
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let manager = Address.fromString("0x0000000000000000000000000000000000000002")
    let sharesAmount = BigInt.fromI32(500)
    let requestId = BigInt.fromI32(1)
    let newWithdrawRequestTokenizedEvent = createWithdrawRequestTokenizedEvent(
      manager, from, to, vault, requestId, sharesAmount
    )
    createMockedFunction(manager, "getWithdrawRequest", "getWithdrawRequest(address,address):((uint256,uint120,uint120),(uint120,uint120,bool))")
      .withArgs([
        ethereum.Value.fromAddress(vault),
        ethereum.Value.fromAddress(from)
      ])
      .returns(
        [
          ethereum.Value.fromTuple(changetype<ethereum.Tuple>([
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(0))
          ])),
          ethereum.Value.fromTuple(changetype<ethereum.Tuple>([
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromBoolean(true)
          ]))
        ]
      )

    createMockedFunction(manager, "getWithdrawRequest", "getWithdrawRequest(address,address):((uint256,uint120,uint120),(uint120,uint120,bool))")
      .withArgs([
        ethereum.Value.fromAddress(vault),
        ethereum.Value.fromAddress(to)
      ])
      .returns(
        [
          ethereum.Value.fromTuple(changetype<ethereum.Tuple>([
            ethereum.Value.fromUnsignedBigInt(requestId),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000))
          ])),
          ethereum.Value.fromTuple(changetype<ethereum.Tuple>([
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromBoolean(false)
          ]))
        ]
      )

    handleWithdrawRequestTokenized(newWithdrawRequestTokenizedEvent)
    let id = manager.toHexString() + ":" + requestId.toString()
    let id1 = manager.toHexString() + ":" + vault.toHexString() + ":" + from.toHexString()

    assert.notInStore("WithdrawRequest", id1)

    assert.fieldEquals("TokenizedWithdrawRequest",
      id,
      "withdrawRequestManager",
      "0x0000000000000000000000000000000000000002"
    )
    assert.fieldEquals("TokenizedWithdrawRequest",
      id,
      "totalYieldTokenAmount",
      "1000"
    )
    assert.fieldEquals("TokenizedWithdrawRequest",
      id,
      "totalWithdraw",
      "0"
    )
    assert.fieldEquals("TokenizedWithdrawRequest",
      id,
      "finalized",
      "false"
    )

    let id2 = manager.toHexString() + ":" + vault.toHexString() + ":" + to.toHexString()
    assert.fieldEquals("WithdrawRequest",
      id2,
      "tokenizedWithdrawRequest",
      id
    )
    assert.fieldEquals("WithdrawRequest",
      id2,
      "withdrawRequestManager",
      "0x0000000000000000000000000000000000000002"
    )
    assert.fieldEquals("WithdrawRequest",
      id2,
      "vault",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals("WithdrawRequest",
      id2,
      "account",
      "0x0000000000000000000000000000000000000004"
    )
    assert.fieldEquals("WithdrawRequest",
      id2,
      "sharesAmount",
      "1000"
    )
  })

  afterEach(() => {
    clearStore()
  })
})