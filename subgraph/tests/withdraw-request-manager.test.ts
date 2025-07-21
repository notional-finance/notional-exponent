import {
  assert,
  describe,
  test,
  beforeEach,
  clearStore,
  afterEach,
  createMockedFunction,
} from "matchstick-as/assembly/index";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  handleApprovedVault,
  handleInitiateWithdrawRequest,
  handleWithdrawRequestTokenized,
} from "../src/withdraw-request-manager";
import { Balance, BalanceSnapshot, TokenizedWithdrawRequest, WithdrawRequest } from "../generated/schema";
import { DEFAULT_PRECISION } from "../src/constants";
import {
  createApprovedVaultEvent,
  createInitiateWithdrawRequestEvent,
  createVault,
  listManager,
  createWithdrawRequestTokenizedEvent,
} from "./common";

let hash1 = Bytes.fromI32(1);
let hash2 = Bytes.fromI32(2);
let hash3 = Bytes.fromI32(3);
let hash4 = Bytes.fromI32(4);
let hash5 = Bytes.fromI32(5);

function setupBalanceSnapshot(vault: Address, account: Address): void {
  let balance = new Balance(account.toHexString() + ":" + vault.toHexString());
  let balanceSnapshot = new BalanceSnapshot(account.toHexString() + ":" + vault.toHexString() + ":0");
  balanceSnapshot.currentBalance = BigInt.fromI32(1000).times(DEFAULT_PRECISION);
  balanceSnapshot.previousBalance = BigInt.zero();
  balanceSnapshot.currentProfitAndLossAtSnapshot = BigInt.zero();
  balanceSnapshot.totalVaultFeesAtSnapshot = BigInt.zero();
  balanceSnapshot.totalInterestAccrualAtSnapshot = BigInt.zero();
  balanceSnapshot.adjustedCostBasis = BigInt.zero();
  balanceSnapshot._lastInterestAccumulator = BigInt.zero();
  balanceSnapshot._lastVaultFeeAccumulator = BigInt.zero();
  balanceSnapshot._accumulatedBalance = BigInt.fromI32(1000).times(DEFAULT_PRECISION);
  balanceSnapshot._accumulatedCostRealized = BigInt.zero();
  balanceSnapshot.balance = balance.id;
  balanceSnapshot.previousSnapshot = null;
  balanceSnapshot.blockNumber = BigInt.fromI32(1);
  balanceSnapshot.timestamp = 1;
  balanceSnapshot.transactionHash = Bytes.fromI32(1);
  balanceSnapshot.save();
  balance.current = balanceSnapshot.id;
  balance.token = vault.toHexString();
  balance.account = account.toHexString();
  balance.firstUpdateBlockNumber = BigInt.fromI32(1);
  balance.firstUpdateTimestamp = 1;
  balance.firstUpdateTransactionHash = Bytes.fromI32(1);
  balance.lastUpdateBlockNumber = BigInt.fromI32(1);
  balance.lastUpdateTimestamp = 1;
  balance.lastUpdateTransactionHash = Bytes.fromI32(1);
  balance.save();

  createMockedFunction(vault, "price", "price(address):(uint256)")
    .withArgs([ethereum.Value.fromAddress(account)])
    .returns([ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000))]);
  createMockedFunction(vault, "strategy", "strategy():(string)").returns([ethereum.Value.fromString("Other")]);
  createMockedFunction(vault, "yieldToken", "yieldToken():(address)").returns([
    ethereum.Value.fromAddress(Address.fromString("0x00000000000000000000000000000000000000ee")),
  ]);
  createMockedFunction(vault, "accountingAsset", "accountingAsset():(address)").returns([
    ethereum.Value.fromAddress(Address.fromString("0x00000000000000000000000000000000000000ff")),
  ]);
  createMockedFunction(vault, "convertToAssets", "convertToAssets(uint256):(uint256)")
    .withArgs([ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION)])
    .returns([ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION)]);
  createMockedFunction(vault, "convertSharesToYieldToken", "convertSharesToYieldToken(uint256):(uint256)")
    .withArgs([ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION)])
    .returns([ethereum.Value.fromUnsignedBigInt(DEFAULT_PRECISION)]);
}

describe("Approve withdraw request manager lists on vault", () => {
  beforeEach(() => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001");
    let manager = Address.fromString("0x0000000000000000000000000000000000000002");
    createVault(vault);
    listManager(vault, manager);
  });

  test("listing multiple withdraw request managers", () => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001");
    let manager = Address.fromString("0x0000000000000000000000000000000000000003");

    assert.fieldEquals(
      "Vault",
      vault.toHexString(),
      "withdrawRequestManagers",
      "[0x0000000000000000000000000000000000000002]",
    );

    listManager(vault, manager);
    assert.fieldEquals(
      "Vault",
      vault.toHexString(),
      "withdrawRequestManagers",
      "[0x0000000000000000000000000000000000000002, 0x0000000000000000000000000000000000000003]",
    );
  });

  test("removing a withdraw request manager", () => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001");
    let manager = Address.fromString("0x0000000000000000000000000000000000000002");
    let isApproved = false;
    let newApprovedVaultEvent = createApprovedVaultEvent(manager, vault, isApproved);
    handleApprovedVault(newApprovedVaultEvent);

    assert.fieldEquals("Vault", vault.toHexString(), "withdrawRequestManagers", "[]");
  });

  afterEach(() => {
    clearStore();
  });
});

describe("Initiate withdraw request", () => {
  beforeEach(() => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001");
    let manager = Address.fromString("0x0000000000000000000000000000000000000002");
    createVault(vault);
    listManager(vault, manager);

    let account = Address.fromString("0x0000000000000000000000000000000000000003");
    let yieldTokenAmount = BigInt.fromI32(1000);
    let sharesAmount = BigInt.fromI32(1000);
    let newInitiateWithdrawRequestEvent = createInitiateWithdrawRequestEvent(
      manager,
      vault,
      account,
      yieldTokenAmount,
      sharesAmount,
    );
    newInitiateWithdrawRequestEvent.transaction.hash = hash1;
    setupBalanceSnapshot(vault, account);
    createMockedFunction(vault, "convertSharesToYieldToken", "convertSharesToYieldToken(uint256):(uint256)")
      .withArgs([ethereum.Value.fromUnsignedBigInt(sharesAmount)])
      .returns([ethereum.Value.fromUnsignedBigInt(yieldTokenAmount)]);
    createMockedFunction(vault, "convertSharesToYieldToken", "convertSharesToYieldToken(uint256):(uint256)")
      .withArgs([ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(500))])
      .returns([ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(500))]);
    handleInitiateWithdrawRequest(newInitiateWithdrawRequestEvent);
  });

  test("initiate withdraw request", () => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001");
    let manager = Address.fromString("0x0000000000000000000000000000000000000002");
    let account = Address.fromString("0x0000000000000000000000000000000000000003");
    let id = manager.toHexString() + ":" + vault.toHexString() + ":" + account.toHexString();

    assert.fieldEquals("WithdrawRequest", id, "requestId", "1");
    assert.fieldEquals("WithdrawRequest", id, "yieldTokenAmount", "1000");
    assert.fieldEquals("WithdrawRequest", id, "sharesAmount", "1000");
    assert.fieldEquals(
      "WithdrawRequest",
      id,
      "balance",
      "0x0000000000000000000000000000000000000003:0x0000000000000000000000000000000000000001",
    );
    assert.fieldEquals("WithdrawRequest", id, "account", "0x0000000000000000000000000000000000000003");
    assert.fieldEquals("WithdrawRequest", id, "vault", "0x0000000000000000000000000000000000000001");
    assert.fieldEquals("WithdrawRequest", id, "withdrawRequestManager", "0x0000000000000000000000000000000000000002");
  });

  test("tokenized withdraw request, split from and to", () => {
    let from = Address.fromString("0x0000000000000000000000000000000000000003");
    let to = Address.fromString("0x0000000000000000000000000000000000000004");
    let vault = Address.fromString("0x0000000000000000000000000000000000000001");
    let manager = Address.fromString("0x0000000000000000000000000000000000000002");
    let sharesAmount = BigInt.fromI32(500);
    let requestId = BigInt.fromI32(1);
    let newWithdrawRequestTokenizedEvent = createWithdrawRequestTokenizedEvent(
      manager,
      from,
      to,
      vault,
      requestId,
      sharesAmount,
    );
    setupBalanceSnapshot(vault, to);
    createMockedFunction(
      manager,
      "getWithdrawRequest",
      "getWithdrawRequest(address,address):((uint256,uint120,uint120),(uint120,uint120,bool))",
    )
      .withArgs([ethereum.Value.fromAddress(vault), ethereum.Value.fromAddress(from)])
      .returns([
        ethereum.Value.fromTuple(
          changetype<ethereum.Tuple>([
            ethereum.Value.fromUnsignedBigInt(requestId),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromUnsignedBigInt(sharesAmount),
          ]),
        ),
        ethereum.Value.fromTuple(
          changetype<ethereum.Tuple>([
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(1000)),
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
      .withArgs([ethereum.Value.fromAddress(vault), ethereum.Value.fromAddress(to)])
      .returns([
        ethereum.Value.fromTuple(
          changetype<ethereum.Tuple>([
            ethereum.Value.fromUnsignedBigInt(requestId),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromUnsignedBigInt(sharesAmount),
          ]),
        ),
        ethereum.Value.fromTuple(
          changetype<ethereum.Tuple>([
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromBoolean(false),
          ]),
        ),
      ]);

    handleWithdrawRequestTokenized(newWithdrawRequestTokenizedEvent);
    let id = manager.toHexString() + ":" + requestId.toString();

    assert.fieldEquals(
      "TokenizedWithdrawRequest",
      id,
      "withdrawRequestManager",
      "0x0000000000000000000000000000000000000002",
    );
    assert.fieldEquals("TokenizedWithdrawRequest", id, "totalYieldTokenAmount", "1000");
    assert.fieldEquals("TokenizedWithdrawRequest", id, "totalWithdraw", "0");
    assert.fieldEquals("TokenizedWithdrawRequest", id, "finalized", "false");

    let id1 = manager.toHexString() + ":" + vault.toHexString() + ":" + from.toHexString();
    assert.fieldEquals("WithdrawRequest", id1, "tokenizedWithdrawRequest", id);
    assert.fieldEquals("WithdrawRequest", id1, "withdrawRequestManager", "0x0000000000000000000000000000000000000002");
    assert.fieldEquals("WithdrawRequest", id1, "vault", "0x0000000000000000000000000000000000000001");
    assert.fieldEquals("WithdrawRequest", id1, "account", "0x0000000000000000000000000000000000000003");
    assert.fieldEquals("WithdrawRequest", id1, "sharesAmount", "500");

    let id2 = manager.toHexString() + ":" + vault.toHexString() + ":" + to.toHexString();
    assert.fieldEquals("WithdrawRequest", id2, "tokenizedWithdrawRequest", id);
    assert.fieldEquals("WithdrawRequest", id2, "withdrawRequestManager", "0x0000000000000000000000000000000000000002");
    assert.fieldEquals("WithdrawRequest", id2, "vault", "0x0000000000000000000000000000000000000001");
    assert.fieldEquals("WithdrawRequest", id2, "account", "0x0000000000000000000000000000000000000004");
    assert.fieldEquals("WithdrawRequest", id2, "sharesAmount", "500");
  });

  test("tokenized withdraw request, split from and to, existing to", () => {
    let from = Address.fromString("0x0000000000000000000000000000000000000003");
    let to = Address.fromString("0x0000000000000000000000000000000000000004");
    let vault = Address.fromString("0x0000000000000000000000000000000000000001");
    let manager = Address.fromString("0x0000000000000000000000000000000000000002");
    let sharesAmount = BigInt.fromI32(500);
    let requestId = BigInt.fromI32(1);
    let newWithdrawRequestTokenizedEvent = createWithdrawRequestTokenizedEvent(
      manager,
      from,
      to,
      vault,
      requestId,
      sharesAmount,
    );
    setupBalanceSnapshot(vault, from);
    setupBalanceSnapshot(vault, to);

    let twr = new TokenizedWithdrawRequest(manager.toHexString() + ":" + requestId.toString());
    twr.lastUpdateBlockNumber = BigInt.fromI32(1);
    twr.lastUpdateTimestamp = 1;
    twr.lastUpdateTransactionHash = Bytes.fromI32(1);
    twr.withdrawRequestManager = manager.toHexString();
    twr.totalYieldTokenAmount = BigInt.fromI32(1000);
    twr.totalWithdraw = BigInt.fromI32(0);
    twr.finalized = false;
    twr.save();

    let w = new WithdrawRequest(manager.toHexString() + ":" + vault.toHexString() + ":" + to.toHexString());
    w.tokenizedWithdrawRequest = twr.id;
    w.withdrawRequestManager = manager.toHexString();
    w.vault = vault.toHexString();
    w.account = to.toHexString();
    w.requestId = requestId;
    w.balance = vault.toHexString() + ":" + to.toHexString();
    w.sharesAmount = sharesAmount;
    w.yieldTokenAmount = BigInt.fromI32(1000);
    w.lastUpdateBlockNumber = BigInt.fromI32(1);
    w.lastUpdateTimestamp = 1;
    w.lastUpdateTransactionHash = Bytes.fromI32(1);
    w.save();

    createMockedFunction(
      manager,
      "getWithdrawRequest",
      "getWithdrawRequest(address,address):((uint256,uint120,uint120),(uint120,uint120,bool))",
    )
      .withArgs([ethereum.Value.fromAddress(vault), ethereum.Value.fromAddress(from)])
      .returns([
        ethereum.Value.fromTuple(
          changetype<ethereum.Tuple>([
            ethereum.Value.fromUnsignedBigInt(requestId),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromUnsignedBigInt(sharesAmount),
          ]),
        ),
        ethereum.Value.fromTuple(
          changetype<ethereum.Tuple>([
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(1000)),
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
      .withArgs([ethereum.Value.fromAddress(vault), ethereum.Value.fromAddress(to)])
      .returns([
        ethereum.Value.fromTuple(
          changetype<ethereum.Tuple>([
            ethereum.Value.fromUnsignedBigInt(requestId),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromUnsignedBigInt(sharesAmount),
          ]),
        ),
        ethereum.Value.fromTuple(
          changetype<ethereum.Tuple>([
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromBoolean(false),
          ]),
        ),
      ]);

    handleWithdrawRequestTokenized(newWithdrawRequestTokenizedEvent);
    let id = manager.toHexString() + ":" + requestId.toString();

    assert.fieldEquals(
      "TokenizedWithdrawRequest",
      id,
      "withdrawRequestManager",
      "0x0000000000000000000000000000000000000002",
    );
    assert.fieldEquals("TokenizedWithdrawRequest", id, "totalYieldTokenAmount", "1000");
    assert.fieldEquals("TokenizedWithdrawRequest", id, "totalWithdraw", "0");
    assert.fieldEquals("TokenizedWithdrawRequest", id, "finalized", "false");

    let id1 = manager.toHexString() + ":" + vault.toHexString() + ":" + from.toHexString();
    assert.fieldEquals("WithdrawRequest", id1, "tokenizedWithdrawRequest", id);
    assert.fieldEquals("WithdrawRequest", id1, "withdrawRequestManager", "0x0000000000000000000000000000000000000002");
    assert.fieldEquals("WithdrawRequest", id1, "vault", "0x0000000000000000000000000000000000000001");
    assert.fieldEquals("WithdrawRequest", id1, "account", "0x0000000000000000000000000000000000000003");
    assert.fieldEquals("WithdrawRequest", id1, "sharesAmount", "500");

    let id2 = manager.toHexString() + ":" + vault.toHexString() + ":" + to.toHexString();
    assert.fieldEquals("WithdrawRequest", id2, "tokenizedWithdrawRequest", id);
    assert.fieldEquals("WithdrawRequest", id2, "withdrawRequestManager", "0x0000000000000000000000000000000000000002");
    assert.fieldEquals("WithdrawRequest", id2, "vault", "0x0000000000000000000000000000000000000001");
    assert.fieldEquals("WithdrawRequest", id2, "account", "0x0000000000000000000000000000000000000004");
    assert.fieldEquals("WithdrawRequest", id2, "sharesAmount", "500");
  });

  test("tokenized withdraw request, delete from", () => {
    let from = Address.fromString("0x0000000000000000000000000000000000000003");
    let to = Address.fromString("0x0000000000000000000000000000000000000004");
    let vault = Address.fromString("0x0000000000000000000000000000000000000001");
    let manager = Address.fromString("0x0000000000000000000000000000000000000002");
    let sharesAmount = BigInt.fromI32(500);
    let requestId = BigInt.fromI32(1);
    let newWithdrawRequestTokenizedEvent = createWithdrawRequestTokenizedEvent(
      manager,
      from,
      to,
      vault,
      requestId,
      sharesAmount,
    );
    createMockedFunction(
      manager,
      "getWithdrawRequest",
      "getWithdrawRequest(address,address):((uint256,uint120,uint120),(uint120,uint120,bool))",
    )
      .withArgs([ethereum.Value.fromAddress(vault), ethereum.Value.fromAddress(from)])
      .returns([
        ethereum.Value.fromTuple(
          changetype<ethereum.Tuple>([
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(0)),
          ]),
        ),
        ethereum.Value.fromTuple(
          changetype<ethereum.Tuple>([
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromBoolean(true),
          ]),
        ),
      ]);

    createMockedFunction(
      manager,
      "getWithdrawRequest",
      "getWithdrawRequest(address,address):((uint256,uint120,uint120),(uint120,uint120,bool))",
    )
      .withArgs([ethereum.Value.fromAddress(vault), ethereum.Value.fromAddress(to)])
      .returns([
        ethereum.Value.fromTuple(
          changetype<ethereum.Tuple>([
            ethereum.Value.fromUnsignedBigInt(requestId),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(1000)),
          ]),
        ),
        ethereum.Value.fromTuple(
          changetype<ethereum.Tuple>([
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(1000)),
            ethereum.Value.fromSignedBigInt(BigInt.fromI32(0)),
            ethereum.Value.fromBoolean(false),
          ]),
        ),
      ]);

    setupBalanceSnapshot(vault, to);
    handleWithdrawRequestTokenized(newWithdrawRequestTokenizedEvent);
    let id = manager.toHexString() + ":" + requestId.toString();
    let id1 = manager.toHexString() + ":" + vault.toHexString() + ":" + from.toHexString();

    assert.notInStore("WithdrawRequest", id1);

    assert.fieldEquals(
      "TokenizedWithdrawRequest",
      id,
      "withdrawRequestManager",
      "0x0000000000000000000000000000000000000002",
    );
    assert.fieldEquals("TokenizedWithdrawRequest", id, "totalYieldTokenAmount", "1000");
    assert.fieldEquals("TokenizedWithdrawRequest", id, "totalWithdraw", "0");
    assert.fieldEquals("TokenizedWithdrawRequest", id, "finalized", "false");

    let id2 = manager.toHexString() + ":" + vault.toHexString() + ":" + to.toHexString();
    assert.fieldEquals("WithdrawRequest", id2, "tokenizedWithdrawRequest", id);
    assert.fieldEquals("WithdrawRequest", id2, "withdrawRequestManager", "0x0000000000000000000000000000000000000002");
    assert.fieldEquals("WithdrawRequest", id2, "vault", "0x0000000000000000000000000000000000000001");
    assert.fieldEquals("WithdrawRequest", id2, "account", "0x0000000000000000000000000000000000000004");
    assert.fieldEquals("WithdrawRequest", id2, "sharesAmount", "1000");
  });

  afterEach(() => {
    clearStore();
  });
});
