import { ponder } from "ponder:registry";

ponder.on(
  "TradingModule:MaxOracleFreshnessUpdated",
  async ({ event, context }) => {
    console.log(event.args);
  },
);

ponder.on("TradingModule:PriceOracleUpdated", async ({ event, context }) => {
  console.log(event.args);
});

ponder.on(
  "TradingModule:TokenPermissionsUpdated",
  async ({ event, context }) => {
    console.log(event.args);
  },
);

ponder.on("TradingModule:TradeExecuted", async ({ event, context }) => {
  console.log(event.args);
});
