import { ApprovedVault, InitiateWithdrawRequest, IWithdrawRequestManager, WithdrawRequestTokenized } from "../generated/templates/WithdrawRequestManager/IWithdrawRequestManager";
import { TokenizedWithdrawRequest, Vault, WithdrawRequest, WithdrawRequestManager } from "../generated/schema";

export function handleApprovedVault(event: ApprovedVault): void {
  let vault = Vault.load(event.params.vault.toHexString());
  if (!vault) return;

  let managers = vault.withdrawRequestManagers;
  if (event.params.isApproved) {
    managers.push(event.address.toHexString());
  } else {
    let index = managers.indexOf(event.address.toHexString());
    if (index !== -1) {
      managers.splice(index, 1);
    }
  }
  vault.withdrawRequestManagers = managers;
  vault.save();

}

export function handleInitiateWithdrawRequest(event: InitiateWithdrawRequest): void {
  let id = event.address.toHexString() + ":" + event.params.vault.toHexString() + ":" + event.params.account.toHexString();
  let withdrawRequest = WithdrawRequest.load(id);
  if (!withdrawRequest) {
    withdrawRequest = new WithdrawRequest(id);
  }
  withdrawRequest.lastUpdateBlockNumber = event.block.number;
  withdrawRequest.lastUpdateTimestamp = event.block.timestamp.toI32();
  withdrawRequest.lastUpdateTransactionHash = event.transaction.hash;

  withdrawRequest.withdrawRequestManager = event.address.toHexString();
  withdrawRequest.account = event.params.account.toHexString();
  withdrawRequest.vault = event.params.vault.toHexString();

  withdrawRequest.requestId = event.params.requestId;
  withdrawRequest.yieldTokenAmount = event.params.yieldTokenAmount;
  withdrawRequest.sharesAmount = event.params.sharesAmount;

  withdrawRequest.save();
}

export function handleWithdrawRequestTokenized(event: WithdrawRequestTokenized): void {
  let id = event.address.toHexString() + ":" + event.params.requestId.toString();
  let twr = TokenizedWithdrawRequest.load(id);
  if (!twr) {
    twr = new TokenizedWithdrawRequest(id);
  }
  twr.lastUpdateBlockNumber = event.block.number;
  twr.lastUpdateTimestamp = event.block.timestamp.toI32();
  twr.lastUpdateTransactionHash = event.transaction.hash;

  twr.withdrawRequestManager = event.address.toHexString();
  let m = IWithdrawRequestManager.bind(event.address);

  // Update the from address
  // TODO: we do not know the vault address here
  let fromW = m.getWithdrawRequest(event.params.from);


  twr.save();
}