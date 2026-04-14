import { Address, ByteArray, Bytes, crypto, ethereum } from "@graphprotocol/graph-ts";
import { Repay, IMorpho } from "../generated/Morpho/IMorpho";
import { Vault } from "../generated/schema";
import { setProfitLossLineItem } from "./entities/balance";
import { loadAccount } from "./entities/account";
import { getBorrowShare, getToken } from "./entities/token";
import { MORPHO_LENDING_ROUTER } from "./constants";
import { IYieldStrategy } from "../generated/templates/LendingRouter/IYieldStrategy";
import { ILendingRouter } from "../generated/templates/LendingRouter/ILendingRouter";
import { getBorrowSharePrice } from "./lending-router";

// Special handling for direct Morpho repayments
export function handleMorphoRepay(event: Repay): void {
  let morpho = IMorpho.bind(event.address);
  let marketParams = morpho.idToMarketParams(event.params.id);
  let vault = Vault.load(marketParams.collateralToken.toHexString());
  // Filter out non vault repayments
  if (!vault) return;
  let vaultAddress = marketParams.collateralToken;
  let isFound = findExitPositionEvent(event.params.onBehalf, vaultAddress, event);
  if (isFound) return;
  let account = loadAccount(event.params.onBehalf.toHexString(), event);
  let borrowShare = getBorrowShare(vaultAddress, Address.fromBytes(MORPHO_LENDING_ROUTER), event);
  let v = IYieldStrategy.bind(vaultAddress);
  let underlyingToken = getToken(v.asset().toHexString());
  let l = ILendingRouter.bind(Address.fromBytes(MORPHO_LENDING_ROUTER));
  let borrowAssetsRepaid = l.convertBorrowSharesToAssets(vaultAddress, event.params.shares);
  let borrowSharePrice = getBorrowSharePrice(borrowAssetsRepaid, event.params.shares, underlyingToken, borrowShare);

  // Only continue if the exit position event is not found
  setProfitLossLineItem(
    account,
    borrowShare,
    underlyingToken,
    // Negative because we are burning borrow shares
    event.params.shares.neg(),
    borrowAssetsRepaid.neg(),
    borrowSharePrice,
    "ExitPosition",
    Address.fromBytes(MORPHO_LENDING_ROUTER),
    event,
  );
}

function findExitPositionEvent(account: Address, vaultAddress: Address, event: ethereum.Event): boolean {
  if (event.receipt === null) return false;

  for (let i = 0; i < event.receipt!.logs.length; i++) {
    let _log = event.receipt!.logs[i];
    if (
      _log.topics[0] == crypto.keccak256(ByteArray.fromUTF8("ExitPosition(address,address,uint256,uint256,uint256)"))
    ) {
      let user = Address.fromBytes(changetype<Bytes>(_log.topics[1].slice(12)));
      let vault = Address.fromBytes(changetype<Bytes>(_log.topics[2].slice(12)));
      if (user.toHexString() === account.toHexString() && vault.toHexString() === vaultAddress.toHexString()) {
        return true;
      }
    }
  }
  return false;
}
