# Foundry Template [![Open in Gitpod][gitpod-badge]][gitpod] [![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![License: MIT][license-badge]][license]

[gitpod]: https://gitpod.io/#https://github.com/notional-finance/notional-v4
[gitpod-badge]: https://img.shields.io/badge/Gitpod-Open%20in%20Gitpod-FFB45B?logo=gitpod
[gha]: https://github.com/notional-finance/notional-v4/actions
[gha-badge]: https://github.com/notional-finance/notional-v4/actions/workflows/ci.yml/badge.svg
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

A Foundry-based template for developing Solidity smart contracts, with sensible defaults.

## What's Inside

- [Forge](https://github.com/foundry-rs/foundry/blob/master/forge): compile, test, fuzz, format, and deploy smart
  contracts
- [Bun]: Foundry defaults to git submodules, but this template uses Node.js packages for managing dependencies
- [Forge Std](https://github.com/foundry-rs/forge-std): collection of helpful contracts and utilities for testing
- [Prettier](https://github.com/prettier/prettier): code formatter for non-Solidity files
- [Solhint](https://github.com/protofire/solhint): linter for Solidity code

## Getting Started

Click the [`Use this template`](https://github.com/PaulRBerg/foundry-template/generate) button at the top of the page to
create a new repository with this repo as the initial state.

Or, if you prefer to install the template manually:

```sh
$ forge init --template PaulRBerg/foundry-template my-project
$ cd my-project
$ bun install # install Solhint, Prettier, and other Node.js deps
```

If this is your first time with Foundry, check out the
[installation](https://github.com/foundry-rs/foundry#installation) instructions.

## Features

This template builds upon the frameworks and libraries mentioned above, so please consult their respective documentation
for details about their specific features.

For example, if you're interested in exploring Foundry in more detail, you should look at the
[Foundry Book](https://book.getfoundry.sh). In particular, you may be interested in reading the
[Writing Tests](https://book.getfoundry.sh/forge/writing-tests.html) tutorial.

### Sensible Defaults

This template comes with a set of sensible default configurations for you to use. These defaults can be found in the
following files:

```text
├── .editorconfig
├── .gitignore
├── .prettierignore
├── .prettierrc.yml
├── .solhint.json
├── foundry.toml
└── remappings.txt
```

### VSCode Integration

This template is IDE agnostic, but for the best user experience, you may want to use it in VSCode alongside Nomic
Foundation's [Solidity extension](https://marketplace.visualstudio.com/items?itemName=NomicFoundation.hardhat-solidity).

For guidance on how to integrate a Foundry project in VSCode, please refer to this
[guide](https://book.getfoundry.sh/config/vscode).

### GitHub Actions

This template comes with GitHub Actions pre-configured. Your contracts will be linted and tested on every push and pull
request made to the `main` branch.

You can edit the CI script in [.github/workflows/ci.yml](./.github/workflows/ci.yml).

## Installing Dependencies

Foundry typically uses git submodules to manage dependencies, but this template uses Node.js packages because
[submodules don't scale](https://twitter.com/PaulRBerg/status/1736695487057531328).

This is how to install dependencies:

1. Install the dependency using your preferred package manager, e.g. `bun install dependency-name`
   - Use this syntax to install from GitHub: `bun install github:username/repo-name`
2. Add a remapping for the dependency in [remappings.txt](./remappings.txt), e.g.
   `dependency-name=node_modules/dependency-name`

Note that OpenZeppelin Contracts is pre-installed, so you can follow that as an example.

## Writing Tests

To write a new test contract, you start by importing `Test` from `forge-std`, and then you inherit it in your test
contract. Forge Std comes with a pre-instantiated [cheatcodes](https://book.getfoundry.sh/cheatcodes/) environment
accessible via the `vm` property. If you would like to view the logs in the terminal output, you can add the `-vvv` flag
and use [console.log](https://book.getfoundry.sh/faq?highlight=console.log#how-do-i-use-consolelog).

This template comes with an example test contract [Foo.t.sol](./tests/Foo.t.sol)

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ forge clean
```

### Compile

Compile the contracts:

```sh
$ forge build
```

### Coverage

Get a test coverage report:

```sh
$ forge coverage
```

### Deploy

Deploy to Anvil:

```sh
$ forge script script/Deploy.s.sol --broadcast --fork-url http://localhost:8545
```

For this script to work, you need to have a `MNEMONIC` environment variable set to a valid
[BIP39 mnemonic](https://iancoleman.io/bip39/).

For instructions on how to deploy to a testnet or mainnet, check out the
[Solidity Scripting](https://book.getfoundry.sh/tutorials/solidity-scripting.html) tutorial.

### Format

Format the contracts:

```sh
$ forge fmt
```

### Gas Usage

Get a gas report:

```sh
$ forge test --gas-report
```

### Lint

Lint the contracts:

```sh
$ bun run lint
```

### Test

Run the tests:

```sh
$ forge test
```

### Test Coverage

Generate test coverage and output result to the terminal:

```sh
$ bun run test:coverage
```

### Test Coverage Report

Generate test coverage with lcov report (you'll have to open the `./coverage/index.html` file in your browser, to do so
simply copy paste the path):

```sh
$ bun run test:coverage:report
```

> [!NOTE]
>
> This command requires you to have [`lcov`](https://github.com/linux-test-project/lcov) installed on your machine. On
> macOS, you can install it with Homebrew: `brew install lcov`.

## Related Efforts

- [foundry-rs/forge-template](https://github.com/foundry-rs/forge-template)
- [abigger87/femplate](https://github.com/abigger87/femplate)
- [cleanunicorn/ethereum-smartcontract-template](https://github.com/cleanunicorn/ethereum-smartcontract-template)
- [FrankieIsLost/forge-template](https://github.com/FrankieIsLost/forge-template)

## Action Runner

The `action_runner.py` script provides a Python-based interface for executing vault operations. It replaces the shell-based approach with better input validation, error handling, and type safety.

### Prerequisites

Before using the action runner, ensure you have:
- Python 3.8+ installed
- Required Python dependencies (install with `pip install -r requirements.txt` if available)
- Environment variables configured in `.env`:
  - `MAINNET_RPC_URL` or `RPC_URL` - Your Ethereum RPC endpoint
  - `API_KEY_ETHERSCAN` - Your Etherscan API key (optional)

### Available Commands

#### 1. Create Initial Position

Supply to Morpho market and enter position on Notional vault.

**Syntax:**
```bash
python action_runner.py create-position <mode> <vault_address> <vault_deposit_amount> <morpho_supply_amount> <morpho_borrow_amount> <min_purchase_amount> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
```

**Arguments (in order):**
- `mode` - Execution mode: `sim` (simulation) or `exec` (execute on-chain)
- `vault_address` - The vault contract address (0x...)
- `vault_deposit_amount` - Vault deposit amount (integer, pre-scaled to asset decimals, e.g., "1000500000000000000000" for 1000.5 tokens with 18 decimals)
- `morpho_supply_amount` - Morpho supply amount (integer, pre-scaled to asset decimals, e.g., "2000000000000000000000" for 2000.0 tokens with 18 decimals)
- `morpho_borrow_amount` - Morpho borrow amount (integer, pre-scaled to asset decimals, e.g., "500000000000000000000" for 500.0 tokens with 18 decimals)
- `min_purchase_amount` - Minimum purchase amount for slippage protection (integer, pre-scaled to asset decimals, e.g., "950000000000000000000")

**Mode-specific options:**
- For `sim` mode: `--sender ADDRESS` (required) - Address to simulate transaction from
- For `exec` mode: `--account NAME` (required) - Named account for transaction signing
- For `exec` mode: `--sender ADDRESS` (required) - Address to send transaction from

**Optional parameters:**
- `--gas-estimate-multiplier MULTIPLIER` - Gas estimate multiplier (integer >100, e.g., 150 for 50% increase)

**Examples:**
```bash
# Simulation mode (amounts pre-scaled for 18 decimal token)
python action_runner.py create-position sim 0x1234567890abcdef1234567890abcdef12345678 1000000000000000000000 2000000000000000000000 500000000000000000000 950000000000000000000 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py create-position exec 0x1234567890abcdef1234567890abcdef12345678 1000000000000000000000 2000000000000000000000 500000000000000000000 950000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12

# With gas estimate multiplier (50% increase)
python action_runner.py create-position exec 0x1234567890abcdef1234567890abcdef12345678 1000000000000000000000 2000000000000000000000 500000000000000000000 950000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12 --gas-estimate-multiplier 150
```

#### 2. Exit Position

Executes an exit position action on a Notional vault.

**Syntax:**
```bash
python action_runner.py exit-position <mode> <vault_address> <shares_to_redeem> <asset_to_repay> <min_purchase_amount> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
```

**Arguments (in order):**
- `mode` - Execution mode: `sim` or `exec`
- `vault_address` - The vault contract address (0x...)
- `shares_to_redeem` - Shares to redeem (integer, pre-scaled to vault share decimals, e.g., "1500000000000000000000000" for 1.5 shares with 24 decimals)
- `asset_to_repay` - Asset amount to repay (integer, pre-scaled to asset decimals)
- `min_purchase_amount` - Minimum purchase amount for slippage protection (integer, pre-scaled to asset decimals)

**Mode-specific options:**
- For `sim` mode: `--sender ADDRESS` (required)
- For `exec` mode: `--account NAME` (required)
- For `exec` mode: `--sender ADDRESS` (required)

**Optional parameters:**
- `--gas-estimate-multiplier MULTIPLIER` - Gas estimate multiplier (integer >100, e.g., 150 for 50% increase)

**Examples:**
```bash
# Simulation mode (1.5 shares with 24 decimals, 500.0 asset with 18 decimals)
python action_runner.py exit-position sim 0x1234567890abcdef1234567890abcdef12345678 1500000000000000000000000 500000000000000000000 950000000000000000000 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py exit-position exec 0x1234567890abcdef1234567890abcdef12345678 1500000000000000000000000 500000000000000000000 950000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12

# With gas estimate multiplier (20% increase)
python action_runner.py exit-position exec 0x1234567890abcdef1234567890abcdef12345678 1500000000000000000000000 500000000000000000000 950000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12 --gas-estimate-multiplier 120
```

#### 3. Exit Position and Max Withdraw from Morpho

Fully exits notional vault position and withdraws all supplied funds to the morpho market.

**Syntax:**
```bash
python action_runner.py exit-position-and-max-withdraw-from-morpho <mode> <vault_address> <min_purchase_amount> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
```

**Arguments (in order):**
- `mode` - Execution mode: `sim` or `exec`
- `vault_address` - The vault contract address (0x...)
- `min_purchase_amount` - Minimum purchase amount for slippage protection (integer, pre-scaled to asset decimals)

**Mode-specific options:**
- For `sim` mode: `--sender ADDRESS` (required)
- For `exec` mode: `--account NAME` (required)
- For `exec` mode: `--sender ADDRESS` (required)

**Optional parameters:**
- `--gas-estimate-multiplier MULTIPLIER` - Gas estimate multiplier (integer >100, e.g., 150 for 50% increase)

**Examples:**
```bash
# Simulation mode (950.0 tokens with 18 decimals)
python action_runner.py exit-position-and-max-withdraw-from-morpho sim 0x1234567890abcdef1234567890abcdef12345678 950000000000000000000 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py exit-position-and-max-withdraw-from-morpho exec 0x1234567890abcdef1234567890abcdef12345678 950000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12

# With gas estimate multiplier (20% increase)
python action_runner.py exit-position-and-max-withdraw-from-morpho exec 0x1234567890abcdef1234567890abcdef12345678 950000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12 --gas-estimate-multiplier 120
```

#### 4. Withdraw from Morpho

Withdraws a specified amount of shares from a Morpho market associated with a vault.

**Syntax:**
```bash
python action_runner.py withdraw-from-morpho <mode> <vault_address> <shares_amount> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
```

**Arguments (in order):**
- `mode` - Execution mode: `sim` or `exec`
- `vault_address` - The vault contract address (0x...)
- `shares_amount` - Shares amount to withdraw (integer, pre-scaled)

**Mode-specific options:**
- For `sim` mode: `--sender ADDRESS` (required)
- For `exec` mode: `--account NAME` (required)
- For `exec` mode: `--sender ADDRESS` (required)

**Optional parameters:**
- `--gas-estimate-multiplier MULTIPLIER` - Gas estimate multiplier (integer >100, e.g., 150 for 50% increase)

**Examples:**
```bash
# Simulation mode (withdrawing 1000.0 shares with 18 decimals)
python action_runner.py withdraw-from-morpho sim 0x1234567890abcdef1234567890abcdef12345678 1000000000000000000000 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py withdraw-from-morpho exec 0x1234567890abcdef1234567890abcdef12345678 1000000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12

# With gas estimate multiplier (30% increase)
python action_runner.py withdraw-from-morpho exec 0x1234567890abcdef1234567890abcdef12345678 1000000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12 --gas-estimate-multiplier 130
```

#### 5. Initiate Withdraw

Initiates a withdraw request for vault assets using vault-specific withdraw data.

**Syntax:**
```bash
python action_runner.py initiate-withdraw <mode> <vault_address> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
```

**Arguments (in order):**
- `mode` - Execution mode: `sim` or `exec`
- `vault_address` - The vault contract address (0x...)

**Mode-specific options:**
- For `sim` mode: `--sender ADDRESS` (required)
- For `exec` mode: `--account NAME` (required)
- For `exec` mode: `--sender ADDRESS` (required)

**Optional parameters:**
- `--gas-estimate-multiplier MULTIPLIER` - Gas estimate multiplier (integer >100, e.g., 150 for 50% increase)

**Examples:**
```bash
# Simulation mode
python action_runner.py initiate-withdraw sim 0x1234567890abcdef1234567890abcdef12345678 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py initiate-withdraw exec 0x1234567890abcdef1234567890abcdef12345678 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12

# With gas estimate multiplier (25% increase)
python action_runner.py initiate-withdraw exec 0x1234567890abcdef1234567890abcdef12345678 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12 --gas-estimate-multiplier 125
```

#### 6. Redeem Vault Shares to Max Leverage

Calculates the precise amount of vault shares to redeem such that the account is left at maximum leverage. Uses Morpho's exact collateral calculation to determine the optimal redemption amount without requiring a rounding buffer.

**Syntax:**
```bash
python action_runner.py redeem-vault-shares-to-max-leverage <mode> <vault_address> <min_purchase_amount> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
```

**Arguments (in order):**
- `mode` - Execution mode: `sim` or `exec`
- `vault_address` - The vault contract address (0x...)
- `min_purchase_amount` - Minimum purchase amount for slippage protection (integer, pre-scaled to asset decimals)

**Mode-specific options:**
- For `sim` mode: `--sender ADDRESS` (required)
- For `exec` mode: `--account NAME` (required)
- For `exec` mode: `--sender ADDRESS` (required)

**Optional parameters:**
- `--gas-estimate-multiplier MULTIPLIER` - Gas estimate multiplier (integer >100, e.g., 150 for 50% increase)

**Examples:**
```bash
# Simulation mode (950.0 tokens with 18 decimals)
python action_runner.py redeem-vault-shares-to-max-leverage sim 0x1234567890abcdef1234567890abcdef12345678 950000000000000000000 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py redeem-vault-shares-to-max-leverage exec 0x1234567890abcdef1234567890abcdef12345678 950000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12

# With gas estimate multiplier (40% increase)
python action_runner.py redeem-vault-shares-to-max-leverage exec 0x1234567890abcdef1234567890abcdef12345678 950000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12 --gas-estimate-multiplier 140
```

**Note:** This command now uses precise mathematical calculations based on Morpho's health factor logic, eliminating the need for manual rounding buffers and providing exact leverage calculations.

#### 7. Flash Liquidate

Performs flash liquidation of an account using Morpho's flash loan functionality to liquidate collateral and repay borrowed assets.

**Syntax:**
```bash
python action_runner.py flash-liquidate <mode> <vault_address> <liquidate_account> <shares_to_liquidate> <assets_to_borrow> <min_purchase_amount> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
```

**Arguments (in order):**
- `mode` - Execution mode: `sim` or `exec`
- `vault_address` - The vault contract address (0x...)
- `liquidate_account` - Address of the account to liquidate (0x...)
- `shares_to_liquidate` - Shares to liquidate (integer, pre-scaled to vault share decimals, e.g., "2000000000000000000000000" for 2.0 shares with 24 decimals)
- `assets_to_borrow` - Assets to borrow via flash loan (integer, pre-scaled to asset decimals)
- `min_purchase_amount` - Minimum purchase amount for slippage protection (integer, pre-scaled to asset decimals)

**Mode-specific options:**
- For `sim` mode: `--sender ADDRESS` (required)
- For `exec` mode: `--account NAME` (required)
- For `exec` mode: `--sender ADDRESS` (required)

**Optional parameters:**
- `--gas-estimate-multiplier MULTIPLIER` - Gas estimate multiplier (integer >100, e.g., 150 for 50% increase)

**Examples:**
```bash
# Simulation mode (2.0 shares with 24 decimals, 1000.0 assets with 18 decimals)
python action_runner.py flash-liquidate sim 0x1234567890abcdef1234567890abcdef12345678 0x9876543210fedcba9876543210fedcba98765432 2000000000000000000000000 1000000000000000000000 950000000000000000000 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py flash-liquidate exec 0x1234567890abcdef1234567890abcdef12345678 0x9876543210fedcba9876543210fedcba98765432 2000000000000000000000000 1000000000000000000000 950000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12

# With gas estimate multiplier (30% increase)
python action_runner.py flash-liquidate exec 0x1234567890abcdef1234567890abcdef12345678 0x9876543210fedcba9876543210fedcba98765432 2000000000000000000000000 1000000000000000000000 950000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12 --gas-estimate-multiplier 130
```

#### 8. View Market Details

Queries and displays market parameters for a vault (simulation only).

**Syntax:**
```bash
python action_runner.py view-market-details <vault_address> [--sender ADDRESS]
```

**Arguments (in order):**
- `vault_address` - The vault contract address (0x...)

**Optional parameters:**
- `--sender ADDRESS` - Sender address for simulation context

**Examples:**
```bash
# Basic market details query
python action_runner.py view-market-details 0x1234567890abcdef1234567890abcdef12345678

# With sender address
python action_runner.py view-market-details 0x1234567890abcdef1234567890abcdef12345678 --sender 0xabcdef1234567890abcdef1234567890abcdef12
```

#### 9. View Account Details

Queries and displays account details including balances and health factors for a specific account in a vault (simulation only).

**Syntax:**
```bash
python action_runner.py view-account-details <vault_address> <account_address> [--sender ADDRESS]
```

**Arguments (in order):**
- `vault_address` - The vault contract address (0x...)
- `account_address` - The account address to query (0x...)

**Optional parameters:**
- `--sender ADDRESS` - Sender address for simulation context

**Examples:**
```bash
# Basic account details query
python action_runner.py view-account-details 0x1234567890abcdef1234567890abcdef12345678 0x9876543210fedcba9876543210fedcba98765432

# With sender address
python action_runner.py view-account-details 0x1234567890abcdef1234567890abcdef12345678 0x9876543210fedcba9876543210fedcba98765432 --sender 0xabcdef1234567890abcdef1234567890abcdef12
```

#### 10. Get Vault Decimals

Retrieves and displays decimal precision information for a vault, including asset decimals, yield token decimals, and vault share decimals.

**Syntax:**
```bash
python action_runner.py get-decimals <vault_address>
```

**Arguments (in order):**
- `vault_address` - The vault contract address (0x...)

**Examples:**
```bash
# Get decimal information for a vault
python action_runner.py get-decimals 0x1234567890abcdef1234567890abcdef12345678
```

**Output:**
The command displays a formatted table showing:
- Vault Address: The queried vault address
- Asset Decimals: Decimal precision of the underlying asset token
- Yield Token Decimals: Decimal precision of the yield-bearing token
- Vault Share Decimals: Decimal precision of the vault shares

This information is useful for understanding the proper scaling when providing integer amounts to other commands.

#### 11. Force Withdraw

Forces the withdrawal of vault shares for a specific account.

**Syntax:**
```bash
python action_runner.py force-withdraw <mode> <vault_address> <account_address> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
```

**Arguments (in order):**
- `mode` - Execution mode: `sim` or `exec`
- `vault_address` - The vault contract address (0x...)
- `account_address` - Address of the account to force withdraw from (0x...)

**Mode-specific options:**
- For `sim` mode: `--sender ADDRESS` (required)
- For `exec` mode: `--account NAME` (required)
- For `exec` mode: `--sender ADDRESS` (required)

**Optional parameters:**
- `--gas-estimate-multiplier MULTIPLIER` - Gas estimate multiplier (integer >100, e.g., 150 for 50% increase)

**Examples:**
```bash
# Simulation mode
python action_runner.py force-withdraw sim 0x1234567890abcdef1234567890abcdef12345678 0x9876543210fedcba9876543210fedcba98765432 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py force-withdraw exec 0x1234567890abcdef1234567890abcdef12345678 0x9876543210fedcba9876543210fedcba98765432 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12
```

#### 12. Finalize Withdraw

Finalizes a previously initiated withdraw request for a specific account.

**Syntax:**
```bash
python action_runner.py finalize-withdraw <mode> <vault_address> <account_address> <wrm_address> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
```

**Arguments (in order):**
- `mode` - Execution mode: `sim` or `exec`
- `vault_address` - The vault contract address (0x...)
- `account_address` - Address of the account to finalize withdraw for (0x...)
- `wrm_address` - Withdraw Request Manager contract address (0x...)

**Mode-specific options:**
- For `sim` mode: `--sender ADDRESS` (required)
- For `exec` mode: `--account NAME` (required)
- For `exec` mode: `--sender ADDRESS` (required)

**Optional parameters:**
- `--gas-estimate-multiplier MULTIPLIER` - Gas estimate multiplier (integer >100, e.g., 150 for 50% increase)

**Examples:**
```bash
# Simulation mode
python action_runner.py finalize-withdraw sim 0x1234567890abcdef1234567890abcdef12345678 0x9876543210fedcba9876543210fedcba98765432 0xabcdef1234567890abcdef1234567890abcdef12 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py finalize-withdraw exec 0x1234567890abcdef1234567890abcdef12345678 0x9876543210fedcba9876543210fedcba98765432 0xabcdef1234567890abcdef1234567890abcdef12 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12
```

#### 13. Liquidate

Liquidates an account's position in a vault.

**Syntax:**
```bash
python action_runner.py liquidate <mode> <vault_address> <liquidate_account> <shares_to_liquidate> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
```

**Arguments (in order):**
- `mode` - Execution mode: `sim` or `exec`
- `vault_address` - The vault contract address (0x...)
- `liquidate_account` - Address of the account to liquidate (0x...)
- `shares_to_liquidate` - Shares to liquidate (integer, pre-scaled to vault share decimals)

**Mode-specific options:**
- For `sim` mode: `--sender ADDRESS` (required)
- For `exec` mode: `--account NAME` (required)
- For `exec` mode: `--sender ADDRESS` (required)

**Optional parameters:**
- `--gas-estimate-multiplier MULTIPLIER` - Gas estimate multiplier (integer >100, e.g., 150 for 50% increase)

**Examples:**
```bash
# Simulation mode
python action_runner.py liquidate sim 0x1234567890abcdef1234567890abcdef12345678 0x9876543210fedcba9876543210fedcba98765432 2000000000000000000000000 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py liquidate exec 0x1234567890abcdef1234567890abcdef12345678 0x9876543210fedcba9876543210fedcba98765432 2000000000000000000000000 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12
```

#### 14. List Supported Vaults

Shows all vault addresses that have registered implementations.

**Syntax:**
```bash
python action_runner.py list-vaults
```

### Important Notes

- **Integer Input Format**: All amount parameters must be provided as pre-scaled integers matching the token's decimal precision (e.g., "1000000000000000000000" for 1000.0 tokens with 18 decimals)
- **Decimal Precision**: Use the `get-decimals` command to determine the correct decimal precision for each vault's assets, yield tokens, and shares
- **Address Validation**: All addresses are validated for proper format
- **Mode Requirements**: 
  - `sim` mode requires `--sender` for transaction simulation
  - `exec` mode requires both `--account` for transaction signing and `--sender` for transaction execution
- **Error Handling**: The script provides detailed error messages for validation failures and execution errors
- **No Automatic Scaling**: Users are responsible for providing correctly scaled integer amounts

### Troubleshooting

- **"No vault implementation found"**: The vault address is not supported. Use `list-vaults` to see available options.
- **"RPC_URL environment variable must be set"**: Configure your `.env` file with a valid Ethereum RPC endpoint.
- **Validation errors**: Check that all addresses are properly formatted and amounts are positive decimals.

## License

This project is licensed under MIT.
