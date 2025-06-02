# Notional Exponent

Notional Exponent is a leveraged yield protocol that creates ERC20 collateral assets that can be deposited into any lending protocol. This approach allows users to get access to novel strategies with advanced features like in place redemption, reward accrual, and sophisticated entry and exit methods while still accessing deep lending liquidity across many lending protocols.

## Address Registry

The address registry is a singleton that holds mappings for admin accounts, lending routers, withdraw request managers, and account positions. It is intended to be non-upgradeable.

## Timelock Upgradeable Proxy

This proxy is used for all vaults, lending routers and withdraw request managers. It is upgradeable with a hardcoded 7 day timelock. It can be paused or unpaused by an emergency pause manager.

## Yield Strategy

A yield strategy is an ERC20 that wraps a "yield token" which represents a position in some sort of strategy. Each yield strategy has a few special characteristics:

- Mints and Redeems must go through a lending router. This ensures that most tokens are held as collateral on a lending protocol.
- All transfers must be approved by a lending router. This is in addition to the normal ERC20 approval allowance. This ensures that collateral held on a lending protocol cannot be withdrawn without first going through the Notional lending router. This exists to ensure that any pre and post liquidation logic can properly execute.
- Provides methods to get the oracle price of shares held by an account. This allows for adjusted valuations in the case of open withdraw requests (or any other non-fungible state).

## Lending Router

A lending router interfaces with a lending protocol to create a position on behalf of a user in a given yield strategy. Currently only Morpho is implemented but this may be extended in the future to support other lending protocols. All actions affecting the user's account must be done through the lending router instead of the lending protocol's native interface (including liquidation). This ensures that any strategy specific logic can run during the transaction.

Because all transfers must first be authorized by the lending router, it is not possible to acquire a native `balanceOf` on a yield strategy and then deposit as collateral on a lending protocol. It is a known issue, however, that an account can enter into a position on a lending router and then borrow up to the maximum allowed LTV against their collateral directly on the lending protocol. Since there may be valuation adjustments from open withdraw requests that the lending protocol would be unaware of, this could put the account into insolvency. The adjustment would have to be greater than the maximum allowed LTV and this is unlikely in practice. Also, in practice, most valuation adjustments would be in the upward direction which would go against the account's borrow capacity.

## Withdraw Request Manager

A withdraw request manager mediates any in place withdraws of staking tokens for a given protocol and a yield strategy. For example, an account borrowing ETH to create a looped weETH position may want to unstake their weETH directly to ETH to avoid trading through an on chain DEX. In this case, they would call `initiateWithdraw` on the lending router and their wstETH tokens would be transferred to the EtherFiWithdrawRequest manager to initiate a redemption on EtherFi directly. Upon finalization, the redeemed ETH would be used to repay any debts and transferred back to the account as profit.

During a withdraw request:

- All of an account's shares must enter the withdraw queue.
- The account cannot mint or redeem shares.
- The account can be liquidated and the liquidator will take control of a portion of their withdraw request.
- The account will cease to earn yield, stop paying fees on their yield tokens, and will not earn any reward tokens. Results for off chain point programs may vary depending on implementation since the account will still appear to have shares in the yield strategy (although their place in the withdraw queue can be detected).

A withdraw request manager also mediates staking into a given protocol.

## Reward Manager

Manages pooled claiming rewards on reward booster pools like Convex or Aura. Also allows for protocols to directly incentive yield strategy positions with tokens.

## Oracles

Custom oracles for yield strategies. Converts the value of a yield token back to USD.

## Trading Module

This contract does not exist in the repository but can be found on chain. It is used in the current Notional V3 leveraged vaults framework. It provides a central oracle registry and interfaces into various on chain DeXes. Any trading via this contract occurs as a delegate call and must first be authorized.

