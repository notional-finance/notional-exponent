import { index, onchainTable, primaryKey } from "ponder";

export const account = onchainTable(
  "account",
  (t) => ({
    account: t.hex().notNull(),
    vault: t.hex().notNull(),
    lendingRouter: t.hex().notNull(),
    lastTransactionTime: t.bigint().notNull(),
    lastTransactionHash: t.hex().notNull(),
    isActive: t.boolean().notNull(),
  }),
  (table) => ({
    pk: primaryKey({ columns: [table.account, table.vault, table.lendingRouter] }),
    accountIdx: index().on(table.account),
    vaultIdx: index().on(table.vault),
    lendingRouterIdx: index().on(table.lendingRouter),
  }),
);
