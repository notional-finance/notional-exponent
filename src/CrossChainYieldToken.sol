// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { Initializable } from "./proxy/Initializable.sol";

/// @notice A yield strategy for when the yield token exists on a different chain. Allows
/// curators on one chain to mint yield tokens on another chain.
contract CrossChainYieldToken is ERC20, ReentrancyGuardTransient, Initializable {
    ERC20 public immutable asset;
    // TODO: this is paired 1-1 with the vault.
    address public immutable vault;

    constructor(address _asset) ERC20("", "") {
        asset = ERC20(_asset);
    }

    /**
     * Storage Variables
     */
    string private s_name;
    string private s_symbol;
    mapping(address account => uint256 assetAmount) public s_pendingAssetStaking;
    mapping(uint256 requestId => uint256 assetsReceived) public s_withdrawAssetsReceived;

    function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return s_name;
    }

    function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return s_symbol;
    }

    function _initialize(bytes calldata data) internal virtual override {
        (string memory _name, string memory _symbol) = abi.decode(data, (string, string));
        s_name = _name;
        s_symbol = _symbol;
    }

    function getPendingAssetStaking(address account) external view returns (uint256) {
        return s_pendingAssetStaking[account];
    }

    function transferAndBridge(address account, uint256 assets, bytes calldata bridgeData) external returns (uint256) {
        // Cannot transfer and bridge additional assets if the account is in a pending state.
        require(s_pendingAssetStaking[account] == 0, "Pending asset staking");

        // Pull the assets from the vault
        uint256 balanceBefore = asset.balanceOf(address(this));
        ERC20(asset).safeTransferFrom(msg.sender, address(this), assets);
        uint256 balanceAfter = asset.balanceOf(address(this));
        require(balanceAfter - balanceBefore == assets);

        // Call the bridge contract to bridge the assets to the other chain
        _callBridge(assets, account, bridgeData);

        // Update the pending asset staking amount for the account
        s_pendingAssetStaking[account] = assets;

        // TODO: This should be minted at a conservative price so that we can end up with
        // more yield tokens than expected. Since yield tokens are typically less in units than
        // asset tokens, this is a little tricky...
        uint256 normalizedYieldTokenAmount = assets * 1e18 / asset.decimals();
        _mint(msg.sender, normalizedYieldTokenAmount);
    }

    function finalizeAssetStaking(address account, uint256 yieldTokenAmount) external {
        require(msg.sender == vault);
        // Cannot finalize asset staking if the account is not in a pending state.
        require(s_pendingAssetStaking[account] > 0, "No pending asset staking");

        // Now we know exactly how many yield tokens the account has received. We will need to
        // do the following:
        //  - The yield tokens are held on the vault.
        //  - A corresponding amount of vault shares are minted to the account and held
        //    by the lending protocol via the lending router.

        // If the yield tokens are less than expected:
        //  - We need to withdraw vault shares from the lending protocol. This might not
        //    be possible if we no longer have approval. If this is case, then maybe we
        //    can simply liquidate the account immediately?
        //  OR
        //  - We can mark down the price of the vault shares for the account using getWithdrawRequestValue,
        //    but this is not ideal since they cannot modify their position anymore.

        // If the yield tokens are more than expected:
        //  - We can mint the yield tokens to the vault, mint the corresponding number
        //    of vault shares to the account and then supply the collateral to the lending protocol.

        delete s_pendingAssetStaking[account];
        // TODO: need to subtract the yield tokens already minted to the account.
        _mint(account, yieldTokenAmount);
    }

    function triggerWithdraw(
        uint256 requestId,
        address account,
        uint256 amount,
        bytes calldata data,
        address forceWithdrawFrom
    )
        external
    {
        require(msg.sender == withdrawRequestManager);
        // Cannot trigger a withdraw if the account is not in a pending state.
        require(s_pendingAssetStaking[msg.sender] > 0, "No pending asset staking");

        _sendMessageToChain(requestId, account, amount, data, forceWithdrawFrom);

        // Burn the yield tokens that were used to trigger the withdraw.
        _burn(msg.sender, amount);
    }

    function finalizeWithdraw(uint256 requestId, uint256 assetsReceived) external {
        require(msg.sender == bridgeContract);
        // We should now receive bridged assets from the other chain.
        // Record the amount of assets received and allow the WRM to finalize the withdraw.
        s_withdrawAssetsReceived[requestId] = assetsReceived;
    }

    function receiveWithdrawAssets(uint256 requestId) external {
        require(msg.sender == withdrawRequestManager);
        // Cannot pull withdraw assets if the request id is not in a pending state.
        uint256 assetsReceived = s_withdrawAssetsReceived[requestId];
        require(assetsReceived > 0, "No withdraw assets received");

        delete s_withdrawAssetsReceived[requestId];
        ERC20(asset).transfer(msg.sender, assetsReceived);
    }
}
