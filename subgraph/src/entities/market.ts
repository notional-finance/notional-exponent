import { Address, Bytes, ethereum } from "@graphprotocol/graph-ts";
import { LendingRouter, Market } from "../../generated/schema";
import { MorphoLendingRouter } from "../../generated/templates/LendingRouter/MorphoLendingRouter";

function createMarket(lendingRouter: Address, vault: Address, event: ethereum.Event, params: Bytes): void {
  let id = vault.toHexString() + ":" + lendingRouter.toHexString();
  let m = Market.load(id);
  if (!m) {
    m = new Market(id);
    m.firstUpdateBlockNumber = event.block.number;
    m.firstUpdateTimestamp = event.block.timestamp.toI32();
    m.firstUpdateTransactionHash = event.transaction.hash;
    m.lendingRouter = lendingRouter.toHexString();
    m.vault = vault.toHexString();
  }

  m.lastUpdateBlockNumber = event.block.number;
  m.lastUpdateTimestamp = event.block.timestamp.toI32();
  m.lastUpdateTransactionHash = event.transaction.hash;
  m.params = params;
  m.save();
}

function setMorphoMarketParams(lendingRouter: Address, vault: Address, event: ethereum.Event): void {
  let id = vault.toHexString() + ":" + lendingRouter.toHexString();
  let m = Market.load(id);
  // This only needs to be done once per vault / lending router combination.
  if (m) return;

  let lr = MorphoLendingRouter.bind(lendingRouter);
  let params = lr.marketParams(vault);
  let encodedParams = ethereum.encode(ethereum.Value.fromTuple(params))!;
  createMarket(lendingRouter, vault, event, encodedParams);
}

export function getMarketParams(lendingRouter: Address, vault: Address, event: ethereum.Event): void {
  let lr = LendingRouter.load(lendingRouter.toHexString());
  if (!lr) return;
  if (lr.name == "Morpho") {
    setMorphoMarketParams(lendingRouter, vault, event);
  }
}
