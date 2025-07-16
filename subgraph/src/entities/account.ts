import { ethereum } from "@graphprotocol/graph-ts";
import { Account } from "../../generated/schema";

export function loadAccount(id: string, event: ethereum.Event): Account {
  let account = Account.load(id);
  if (!account) {
    account = new Account(id);
    account.firstUpdateBlockNumber = event.block.number;
    account.firstUpdateTimestamp = event.block.timestamp.toI32();
    account.firstUpdateTransactionHash = event.transaction.hash;
  }

  account.lastUpdateBlockNumber = event.block.number;
  account.lastUpdateTimestamp = event.block.timestamp.toI32();
  account.lastUpdateTransactionHash = event.transaction.hash;
  account.systemAccountType = "None";

  account.save();
  return account;
}
