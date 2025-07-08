import { newMockEvent } from "matchstick-as"
import { ethereum, Address } from "@graphprotocol/graph-ts"
import {
  AccountPositionCleared,
  AccountPositionCreated,
  FeeReceiverTransferred,
  PauseAdminTransferred,
  PendingPauseAdminSet,
  PendingUpgradeAdminSet,
  UpgradeAdminTransferred,
} from "../generated/AddressRegistry/AddressRegistry"

export function createAccountPositionClearedEvent(
  account: Address,
  vault: Address,
  lendingRouter: Address
): AccountPositionCleared {
  let accountPositionClearedEvent =
    changetype<AccountPositionCleared>(newMockEvent())

  accountPositionClearedEvent.parameters = new Array()

  accountPositionClearedEvent.parameters.push(
    new ethereum.EventParam("account", ethereum.Value.fromAddress(account))
  )
  accountPositionClearedEvent.parameters.push(
    new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault))
  )
  accountPositionClearedEvent.parameters.push(
    new ethereum.EventParam(
      "lendingRouter",
      ethereum.Value.fromAddress(lendingRouter)
    )
  )

  return accountPositionClearedEvent
}

export function createAccountPositionCreatedEvent(
  account: Address,
  vault: Address,
  lendingRouter: Address
): AccountPositionCreated {
  let accountPositionCreatedEvent =
    changetype<AccountPositionCreated>(newMockEvent())

  accountPositionCreatedEvent.parameters = new Array()

  accountPositionCreatedEvent.parameters.push(
    new ethereum.EventParam("account", ethereum.Value.fromAddress(account))
  )
  accountPositionCreatedEvent.parameters.push(
    new ethereum.EventParam("vault", ethereum.Value.fromAddress(vault))
  )
  accountPositionCreatedEvent.parameters.push(
    new ethereum.EventParam(
      "lendingRouter",
      ethereum.Value.fromAddress(lendingRouter)
    )
  )

  return accountPositionCreatedEvent
}

export function createFeeReceiverTransferredEvent(
  newFeeReceiver: Address
): FeeReceiverTransferred {
  let feeReceiverTransferredEvent =
    changetype<FeeReceiverTransferred>(newMockEvent())

  feeReceiverTransferredEvent.parameters = new Array()

  feeReceiverTransferredEvent.parameters.push(
    new ethereum.EventParam(
      "newFeeReceiver",
      ethereum.Value.fromAddress(newFeeReceiver)
    )
  )

  return feeReceiverTransferredEvent
}

export function createPauseAdminTransferredEvent(
  newPauseAdmin: Address
): PauseAdminTransferred {
  let pauseAdminTransferredEvent =
    changetype<PauseAdminTransferred>(newMockEvent())

  pauseAdminTransferredEvent.parameters = new Array()

  pauseAdminTransferredEvent.parameters.push(
    new ethereum.EventParam(
      "newPauseAdmin",
      ethereum.Value.fromAddress(newPauseAdmin)
    )
  )

  return pauseAdminTransferredEvent
}

export function createPendingPauseAdminSetEvent(
  newPendingPauseAdmin: Address
): PendingPauseAdminSet {
  let pendingPauseAdminSetEvent =
    changetype<PendingPauseAdminSet>(newMockEvent())

  pendingPauseAdminSetEvent.parameters = new Array()

  pendingPauseAdminSetEvent.parameters.push(
    new ethereum.EventParam(
      "newPendingPauseAdmin",
      ethereum.Value.fromAddress(newPendingPauseAdmin)
    )
  )

  return pendingPauseAdminSetEvent
}

export function createPendingUpgradeAdminSetEvent(
  newPendingUpgradeAdmin: Address
): PendingUpgradeAdminSet {
  let pendingUpgradeAdminSetEvent =
    changetype<PendingUpgradeAdminSet>(newMockEvent())

  pendingUpgradeAdminSetEvent.parameters = new Array()

  pendingUpgradeAdminSetEvent.parameters.push(
    new ethereum.EventParam(
      "newPendingUpgradeAdmin",
      ethereum.Value.fromAddress(newPendingUpgradeAdmin)
    )
  )

  return pendingUpgradeAdminSetEvent
}

export function createUpgradeAdminTransferredEvent(
  newUpgradeAdmin: Address
): UpgradeAdminTransferred {
  let upgradeAdminTransferredEvent =
    changetype<UpgradeAdminTransferred>(newMockEvent())

  upgradeAdminTransferredEvent.parameters = new Array()

  upgradeAdminTransferredEvent.parameters.push(
    new ethereum.EventParam(
      "newUpgradeAdmin",
      ethereum.Value.fromAddress(newUpgradeAdmin)
    )
  )

  return upgradeAdminTransferredEvent
}
