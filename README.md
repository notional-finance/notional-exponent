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

Creates a new position in a supported vault.

**Syntax:**
```bash
python action_runner.py create-position <mode> <vault_address> <initial_deposit> <initial_supply> <initial_borrow> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
```

**Arguments (in order):**
- `mode` - Execution mode: `sim` (simulation) or `exec` (execute on-chain)
- `vault_address` - The vault contract address (0x...)
- `initial_deposit` - Initial deposit amount (decimal format, e.g., "1000.5")
- `initial_supply` - Initial supply amount (decimal format, e.g., "2000.0")
- `initial_borrow` - Initial borrow amount (decimal format, e.g., "500.0")

**Mode-specific options:**
- For `sim` mode: `--sender ADDRESS` (required) - Address to simulate transaction from
- For `exec` mode: `--account NAME` (required) - Named account for transaction signing
- For `exec` mode: `--sender ADDRESS` (required) - Address to send transaction from

**Optional parameters:**
- `--gas-estimate-multiplier MULTIPLIER` - Gas estimate multiplier (integer >100, e.g., 150 for 50% increase)

**Examples:**
```bash
# Simulation mode
python action_runner.py create-position sim 0x1234567890abcdef1234567890abcdef12345678 1000.0 2000.0 500.0 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py create-position exec 0x1234567890abcdef1234567890abcdef12345678 1000.0 2000.0 500.0 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12

# With gas estimate multiplier (50% increase)
python action_runner.py create-position exec 0x1234567890abcdef1234567890abcdef12345678 1000.0 2000.0 500.0 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12 --gas-estimate-multiplier 150
```

#### 2. Exit Position and Withdraw

Exits an existing position and withdraws funds from Morpho.

**Syntax:**
```bash
python action_runner.py exit-position <mode> <vault_address> <min_purchase_amount> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
```

**Arguments (in order):**
- `mode` - Execution mode: `sim` or `exec`
- `vault_address` - The vault contract address (0x...)
- `min_purchase_amount` - Minimum purchase amount for slippage protection (decimal format)

**Mode-specific options:**
- For `sim` mode: `--sender ADDRESS` (required)
- For `exec` mode: `--account NAME` (required)
- For `exec` mode: `--sender ADDRESS` (required)

**Optional parameters:**
- `--gas-estimate-multiplier MULTIPLIER` - Gas estimate multiplier (integer >100, e.g., 150 for 50% increase)

**Examples:**
```bash
# Simulation mode
python action_runner.py exit-position sim 0x1234567890abcdef1234567890abcdef12345678 950.0 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py exit-position exec 0x1234567890abcdef1234567890abcdef12345678 950.0 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12

# With gas estimate multiplier (20% increase)
python action_runner.py exit-position exec 0x1234567890abcdef1234567890abcdef12345678 950.0 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12 --gas-estimate-multiplier 120
```

#### 3. Withdraw from Morpho

Withdraws all supplied assets from a Morpho market associated with a vault.

**Syntax:**
```bash
python action_runner.py withdraw-from-morpho <mode> <vault_address> [--sender ADDRESS] [--account NAME] [--gas-estimate-multiplier MULTIPLIER]
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
python action_runner.py withdraw-from-morpho sim 0x1234567890abcdef1234567890abcdef12345678 --sender 0xabcdef1234567890abcdef1234567890abcdef12

# Execution mode
python action_runner.py withdraw-from-morpho exec 0x1234567890abcdef1234567890abcdef12345678 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12

# With gas estimate multiplier (30% increase)
python action_runner.py withdraw-from-morpho exec 0x1234567890abcdef1234567890abcdef12345678 --account my-wallet --sender 0xabcdef1234567890abcdef1234567890abcdef12 --gas-estimate-multiplier 130
```

#### 4. Initiate Withdraw

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

#### 5. List Supported Vaults

Shows all vault addresses that have registered implementations.

**Syntax:**
```bash
python action_runner.py list-vaults
```

### Important Notes

- **Decimal Input Format**: All amount parameters accept decimal notation (e.g., "1000.5", "0.001")
- **Address Validation**: All addresses are validated for proper format
- **Mode Requirements**: 
  - `sim` mode requires `--sender` for transaction simulation
  - `exec` mode requires both `--account` for transaction signing and `--sender` for transaction execution
- **Error Handling**: The script provides detailed error messages for validation failures and execution errors
- **Scaling**: User inputs are automatically scaled to the appropriate decimal precision for each vault

### Troubleshooting

- **"No vault implementation found"**: The vault address is not supported. Use `list-vaults` to see available options.
- **"RPC_URL environment variable must be set"**: Configure your `.env` file with a valid Ethereum RPC endpoint.
- **Validation errors**: Check that all addresses are properly formatted and amounts are positive decimals.

## License

This project is licensed under MIT.
