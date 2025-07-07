import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { Address } from "@graphprotocol/graph-ts"
import { handleAccountPositionCreated, handleLendingRouterSet } from "../src/address-registry"
import { createAccountPositionCreatedEvent, createLendingRouterSetEvent } from "./address-registry-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/subgraphs/developing/creating/unit-testing-framework/#tests-structure

describe("Create account assertions", () => {
  beforeAll(() => {
    let account = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let lendingRouter = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let newAccountPositionCreatedEvent = createAccountPositionCreatedEvent(
      account,
      vault,
      lendingRouter
    )
    handleAccountPositionCreated(newAccountPositionCreatedEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/subgraphs/developing/creating/unit-testing-framework/#write-a-unit-test

  test("Account created and stored", () => {
    assert.entityCount("Account", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "Account",
      "0x0000000000000000000000000000000000000001",
      "systemAccountType",
      "None"
    )

    // More assert options:
    // https://thegraph.com/docs/en/subgraphs/developing/creating/unit-testing-framework/#asserts
  })
})

describe("Whitelist lending router assertions", () => {
  beforeAll(() => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let lendingRouter = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let newLendingRouterSetEvent = createLendingRouterSetEvent(lendingRouter)
    handleLendingRouterSet(newLendingRouterSetEvent)
  })

  afterAll(() => {
    clearStore()
  })

  test("Lending router created and stored", () => {
    assert.entityCount("LendingRouter", 1)

    assert.fieldEquals(
      "LendingRouter",
      "0x0000000000000000000000000000000000000001",
      "id",
      "0x0000000000000000000000000000000000000001"
    )
  })
})