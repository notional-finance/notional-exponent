import { ponder } from "ponder:registry";

ponder.on(
  "AddressRegistry:AccountPositionCleared",
  async ({ event, context }) => {
    console.log(event.args);
  },
);

ponder.on(
  "AddressRegistry:AccountPositionCreated",
  async ({ event, context }) => {
    console.log(event.args);
  },
);

ponder.on(
  "AddressRegistry:FeeReceiverTransferred",
  async ({ event, context }) => {
    console.log(event.args);
  },
);

ponder.on("AddressRegistry:LendingRouterSet", async ({ event, context }) => {
  console.log(event.args);
});
