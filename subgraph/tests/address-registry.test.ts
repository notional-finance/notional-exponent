import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll,
  createMockedFunction,
  newMockEvent,
} from "matchstick-as/assembly/index";
import { Address, BigInt, ethereum } from "@graphprotocol/graph-ts";
import {
  handleLendingRouterSet,
  handleWhitelistedVault,
  handleWithdrawRequestManagerSet,
} from "../src/address-registry";
import {
  LendingRouterSet,
  WhitelistedVault,
  WithdrawRequestManagerSet,
} from "../generated/AddressRegistry/AddressRegistry";

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/subgraphs/developing/creating/unit-testing-framework/#tests-structure

export function createLendingRouterSetEvent(lendingRouter: Address): LendingRouterSet {
  let lendingRouterSetEvent = changetype<LendingRouterSet>(newMockEvent());

  lendingRouterSetEvent.parameters = new Array();

  lendingRouterSetEvent.parameters.push(
    new ethereum.EventParam("lendingRouter", ethereum.Value.fromAddress(lendingRouter)),
  );

  return lendingRouterSetEvent;
}

export function createWhitelistedVaultEvent(vault: Address, isWhitelisted: boolean): WhitelistedVault {
  let whitelistedVaultEvent = changetype<WhitelistedVault>(newMockEvent());

  whitelistedVaultEvent.parameters = new Array();

  whitelistedVaultEvent.parameters.push(new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault)));
  whitelistedVaultEvent.parameters.push(
    new ethereum.EventParam("isWhitelisted", ethereum.Value.fromBoolean(isWhitelisted)),
  );

  return whitelistedVaultEvent;
}

export function createWithdrawRequestManagerSetEvent(
  yieldToken: Address,
  withdrawRequestManager: Address,
): WithdrawRequestManagerSet {
  let withdrawRequestManagerSetEvent = changetype<WithdrawRequestManagerSet>(newMockEvent());

  withdrawRequestManagerSetEvent.parameters = new Array();

  withdrawRequestManagerSetEvent.parameters.push(
    new ethereum.EventParam("yieldToken", ethereum.Value.fromAddress(yieldToken)),
  );
  withdrawRequestManagerSetEvent.parameters.push(
    new ethereum.EventParam("withdrawRequestManager", ethereum.Value.fromAddress(withdrawRequestManager)),
  );

  return withdrawRequestManagerSetEvent;
}

function assertTokenFields(token: string, name: string, symbol: string, tokenType: string): void {
  assert.fieldEquals("Token", token, "name", name);
  assert.fieldEquals("Token", token, "symbol", symbol);
  assert.fieldEquals("Token", token, "decimals", "18");
  assert.fieldEquals("Token", token, "tokenType", tokenType);
}

describe("Whitelist lending router assertions", () => {
  beforeAll(() => {
    let lendingRouter = Address.fromString("0x0000000000000000000000000000000000000001");
    let newLendingRouterSetEvent = createLendingRouterSetEvent(lendingRouter);
    createMockedFunction(lendingRouter, "name", "name():(string)").returns([ethereum.Value.fromString("Morpho")]);

    handleLendingRouterSet(newLendingRouterSetEvent);
  });

  afterAll(() => {
    clearStore();
  });

  test("Lending router created and stored", () => {
    assert.entityCount("LendingRouter", 1);

    assert.fieldEquals(
      "LendingRouter",
      "0x0000000000000000000000000000000000000001",
      "id",
      "0x0000000000000000000000000000000000000001",
    );

    assert.dataSourceExists("LendingRouter", "0x0000000000000000000000000000000000000001");
  });
});

describe("Whitelist vault assertions", () => {
  beforeAll(() => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001");
    let yieldToken = Address.fromString("0x0000000000000000000000000000000000000002");
    let asset = Address.fromString("0x0000000000000000000000000000000000000003");
    let newWhitelistedVaultEvent = createWhitelistedVaultEvent(vault, true);

    createMockedFunction(vault, "feeRate", "feeRate():(uint256)").returns([
      ethereum.Value.fromSignedBigInt(BigInt.fromI32(10).pow(16)),
    ]);
    createMockedFunction(vault, "yieldToken", "yieldToken():(address)").returns([
      ethereum.Value.fromAddress(yieldToken),
    ]);
    createMockedFunction(vault, "asset", "asset():(address)").returns([ethereum.Value.fromAddress(asset)]);
    createMockedFunction(vault, "name", "name():(string)").returns([ethereum.Value.fromString("Vault")]);
    createMockedFunction(vault, "symbol", "symbol():(string)").returns([ethereum.Value.fromString("VAULT")]);
    createMockedFunction(vault, "decimals", "decimals():(uint8)").returns([ethereum.Value.fromI32(18)]);
    createMockedFunction(vault, "strategy", "strategy():(string)").returns([ethereum.Value.fromString("Staking")]);

    createMockedFunction(yieldToken, "name", "name():(string)").returns([ethereum.Value.fromString("Yield Token")]);
    createMockedFunction(yieldToken, "symbol", "symbol():(string)").returns([ethereum.Value.fromString("YIELD")]);
    createMockedFunction(yieldToken, "decimals", "decimals():(uint8)").returns([ethereum.Value.fromI32(18)]);

    createMockedFunction(asset, "name", "name():(string)").returns([ethereum.Value.fromString("Asset")]);
    createMockedFunction(asset, "symbol", "symbol():(string)").returns([ethereum.Value.fromString("ASSET")]);
    createMockedFunction(asset, "decimals", "decimals():(uint8)").returns([ethereum.Value.fromI32(18)]);

    handleWhitelistedVault(newWhitelistedVaultEvent);
  });

  test("Vault created and stored", () => {
    assert.entityCount("Vault", 1);
    assert.fieldEquals(
      "Vault",
      "0x0000000000000000000000000000000000000001",
      "id",
      "0x0000000000000000000000000000000000000001",
    );
    assert.fieldEquals("Vault", "0x0000000000000000000000000000000000000001", "isWhitelisted", "true");
    assert.fieldEquals(
      "Vault",
      "0x0000000000000000000000000000000000000001",
      "feeRate",
      BigInt.fromI32(10).pow(16).toString(),
    );
    assert.fieldEquals(
      "Vault",
      "0x0000000000000000000000000000000000000001",
      "yieldToken",
      "0x0000000000000000000000000000000000000002",
    );
    assert.fieldEquals(
      "Vault",
      "0x0000000000000000000000000000000000000001",
      "asset",
      "0x0000000000000000000000000000000000000003",
    );
    assert.fieldEquals(
      "Vault",
      "0x0000000000000000000000000000000000000001",
      "vaultToken",
      "0x0000000000000000000000000000000000000001",
    );
    assert.fieldEquals("Vault", "0x0000000000000000000000000000000000000001", "withdrawRequestManagers", "[]");

    // Check vault token features
    assert.fieldEquals(
      "Token",
      "0x0000000000000000000000000000000000000001",
      "vaultAddress",
      "0x0000000000000000000000000000000000000001",
    );
    assert.fieldEquals(
      "Token",
      "0x0000000000000000000000000000000000000001",
      "underlying",
      "0x0000000000000000000000000000000000000003",
    );

    assert.entityCount("Token", 3);
    assertTokenFields("0x0000000000000000000000000000000000000002", "Yield Token", "YIELD", "Underlying");
    assertTokenFields("0x0000000000000000000000000000000000000003", "Asset", "ASSET", "Underlying");
    assertTokenFields("0x0000000000000000000000000000000000000001", "Vault", "VAULT", "VaultShare");

    assert.dataSourceExists("Vault", "0x0000000000000000000000000000000000000001");
  });

  afterAll(() => {
    clearStore();
  });
});

describe("Whitelist withdraw request manager assertions", () => {
  beforeAll(() => {
    let withdrawRequestManager = Address.fromString("0x0000000000000000000000000000000000000001");
    let yieldToken = Address.fromString("0x0000000000000000000000000000000000000002");
    let withdrawToken = Address.fromString("0x0000000000000000000000000000000000000003");
    let stakingToken = Address.fromString("0x0000000000000000000000000000000000000004");
    let newWhitelistedWithdrawRequestManagerEvent = createWithdrawRequestManagerSetEvent(
      yieldToken,
      withdrawRequestManager,
    );

    createMockedFunction(withdrawRequestManager, "YIELD_TOKEN", "YIELD_TOKEN():(address)").returns([
      ethereum.Value.fromAddress(yieldToken),
    ]);
    createMockedFunction(withdrawRequestManager, "WITHDRAW_TOKEN", "WITHDRAW_TOKEN():(address)").returns([
      ethereum.Value.fromAddress(withdrawToken),
    ]);
    createMockedFunction(withdrawRequestManager, "STAKING_TOKEN", "STAKING_TOKEN():(address)").returns([
      ethereum.Value.fromAddress(stakingToken),
    ]);

    createMockedFunction(yieldToken, "name", "name():(string)").returns([ethereum.Value.fromString("Yield Token")]);
    createMockedFunction(yieldToken, "symbol", "symbol():(string)").returns([ethereum.Value.fromString("YIELD")]);
    createMockedFunction(yieldToken, "decimals", "decimals():(uint8)").returns([ethereum.Value.fromI32(18)]);

    createMockedFunction(withdrawToken, "name", "name():(string)").returns([
      ethereum.Value.fromString("Withdraw Token"),
    ]);
    createMockedFunction(withdrawToken, "symbol", "symbol():(string)").returns([ethereum.Value.fromString("WITHDRAW")]);
    createMockedFunction(withdrawToken, "decimals", "decimals():(uint8)").returns([ethereum.Value.fromI32(18)]);

    createMockedFunction(stakingToken, "name", "name():(string)").returns([ethereum.Value.fromString("Staking Token")]);
    createMockedFunction(stakingToken, "symbol", "symbol():(string)").returns([ethereum.Value.fromString("STAKING")]);
    createMockedFunction(stakingToken, "decimals", "decimals():(uint8)").returns([ethereum.Value.fromI32(18)]);

    handleWithdrawRequestManagerSet(newWhitelistedWithdrawRequestManagerEvent);
  });

  test("Withdraw request manager created and stored", () => {
    assert.entityCount("WithdrawRequestManager", 1);
    assert.fieldEquals(
      "WithdrawRequestManager",
      "0x0000000000000000000000000000000000000001",
      "id",
      "0x0000000000000000000000000000000000000001",
    );
    assert.fieldEquals(
      "WithdrawRequestManager",
      "0x0000000000000000000000000000000000000001",
      "yieldToken",
      "0x0000000000000000000000000000000000000002",
    );
    assert.fieldEquals(
      "WithdrawRequestManager",
      "0x0000000000000000000000000000000000000001",
      "withdrawToken",
      "0x0000000000000000000000000000000000000003",
    );
    assert.fieldEquals(
      "WithdrawRequestManager",
      "0x0000000000000000000000000000000000000001",
      "stakingToken",
      "0x0000000000000000000000000000000000000004",
    );

    assert.entityCount("Token", 3);
    assertTokenFields("0x0000000000000000000000000000000000000002", "Yield Token", "YIELD", "Underlying");
    assertTokenFields("0x0000000000000000000000000000000000000003", "Withdraw Token", "WITHDRAW", "Underlying");
    assertTokenFields("0x0000000000000000000000000000000000000004", "Staking Token", "STAKING", "Underlying");

    assert.dataSourceExists("WithdrawRequestManager", "0x0000000000000000000000000000000000000001");
  });
});
