import { ponder } from "ponder:registry";
import { account } from "../ponder.schema";

ponder.on("AddressRegistry:AccountPositionCleared", async ({ event, context }) => {
  await context.db
    .insert(account)
    .values({
      account: event.args.account,
      vault: event.args.vault,
      lendingRouter: event.args.lendingRouter,
      lastTransactionTime: event.block.timestamp,
      lastTransactionHash: event.transaction.hash,
      isActive: false,
    })
    .onConflictDoUpdate({
      lastTransactionTime: event.block.timestamp,
      lastTransactionHash: event.transaction.hash,
      isActive: false,
    });
});

ponder.on("AddressRegistry:AccountPositionCreated", async ({ event, context }) => {
  await context.db
    .insert(account)
    .values({
      account: event.args.account,
      vault: event.args.vault,
      lendingRouter: event.args.lendingRouter,
      lastTransactionTime: event.block.timestamp,
      lastTransactionHash: event.transaction.hash,
      isActive: true,
    })
    .onConflictDoUpdate({
      lastTransactionTime: event.block.timestamp,
      lastTransactionHash: event.transaction.hash,
      isActive: true,
    });
});
