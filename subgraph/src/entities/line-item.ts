import { ethereum, BigInt } from "@graphprotocol/graph-ts";
import { Account, ProfitLossLineItem, Token } from "../../generated/schema";
import { DEFAULT_PRECISION } from "../constants";
import { updateAccount } from "./balance";

// Transfer Types are:
// 1. Vault Share Mint (enterPosition)
// 2. Vault Share Burn (exitPosition)
// 3. Vault Debt Mint (enterPosition or migratePosition)
// 4. Vault Debt Burn (exitPosition or migratePosition)
//    Position Migrated (Vault Debt Burn => Vault Debt Mint)
// 5. Withdraw Request Initiated
// 6. Withdraw Request Tokenized & Transferred
// 7. Withdraw Request Finalized
// 8. Withdraw Request Burned => Vault Share Burn (exitPosition)

// For each one we need to know:
// bundleName: (Action Type)
// underlyingAmountRealized (transferred amount * realizedPrice)
// underlyingAmountSpot (burned or minted amount * oracle price)
// realizedPrice (burned or minted amount / transferred amount)
// spotPrice (oracle price)
// impliedFixedRate