import { describe, test, afterAll, beforeAll, clearStore, newMockEvent } from "matchstick-as/assembly/index";
import { Address, ethereum } from "@graphprotocol/graph-ts";
import { ApprovedVault } from "../generated/templates/WithdrawRequestManager/IWithdrawRequestManager";
import { handleApprovedVault } from "../src/withdraw-request-manager";

function createApprovedVaultEvent(
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

  return approvedVaultEvent
}

describe("Approve withdraw request manager lists on vault", () => {
  beforeAll(() => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let isApproved = true
    let newApprovedVaultEvent = createApprovedVaultEvent(vault, isApproved)
    handleApprovedVault(newApprovedVaultEvent)
  })

  test("listing multiple withdraw request managers", () => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let isApproved = true
    let newApprovedVaultEvent = createApprovedVaultEvent(vault, isApproved)
    handleApprovedVault(newApprovedVaultEvent)
  })

  test("removing a withdraw request manager", () => {
    let vault = Address.fromString("0x0000000000000000000000000000000000000001")
    let isApproved = false
    let newApprovedVaultEvent = createApprovedVaultEvent(vault, isApproved)
    handleApprovedVault(newApprovedVaultEvent)
  })

  afterAll(() => {
    clearStore()
  })
})

describe("Initiate withdraw request", () => {
  test("initiate withdraw request", () => {})
  test("tokenized withdraw request, split from and to", () => {})
  test("tokenized withdraw request, split from and to, existing to", () => {})
  test("tokenized withdraw request, delete from", () => {})
})