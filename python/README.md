# Python Action Runner

A Python-based replacement for the shell script `createInitialPosition.sh` that provides a more robust, type-safe, and extensible way to interact with vault actions.

## Overview

This system replaces the previous Solidity-based vault data processing with a Python implementation that:
- Uses Web3.py to fetch blockchain data directly
- Provides proper ABI encoding for complex data structures
- Supports multiple vault implementations through a registry system
- Offers better error handling and input validation
- Maintains compatibility with existing Forge-based action scripts

## Installation

1. Install Python dependencies:
```bash
pip install -r requirements.txt
```

2. Ensure your environment variables are set:
```bash
# In your .env file or environment
export MAINNET_RPC_URL="your_rpc_url_here"
export API_KEY_ETHERSCAN="your_etherscan_key"  # Optional
```

## Usage

### Basic Commands

The action runner supports three main commands:

#### 1. Create Initial Position
```bash
python action_runner.py create-position <mode> <vault_address> <initial_deposit> <initial_supply> <initial_borrow> [options]
```

**Simulation mode:**
```bash
python action_runner.py create-position sim 0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae 1000 2000 500 --sender 0x1234567890123456789012345678901234567890
```

**Execution mode:**
```bash
python action_runner.py create-position exec 0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae 1000 2000 500 --account myaccount
```

#### 2. Exit Position and Withdraw
```bash
python action_runner.py exit-position <mode> <vault_address> <initial_deposit> <initial_supply> <initial_borrow> <min_purchase_amount> [options]
```

**Example:**
```bash
python action_runner.py exit-position sim 0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae 1000 2000 500 950 --sender 0x1234567890123456789012345678901234567890
```

#### 3. List Supported Vaults
```bash
python action_runner.py list-vaults
```

**Note:** Since `action_runner.py` is in the root directory, run these commands from the project root, not from the `python/` subdirectory.

### Parameters

- **mode**: Either `sim` (simulation) or `exec` (execution)
- **vault_address**: Ethereum address of the vault contract
- **initial_deposit/supply/borrow**: Amounts in human-readable format (e.g., "1000" for 1000 tokens)
- **min_purchase_amount**: Minimum amount for redeem operations
- **--sender**: Ethereum address for simulation mode
- **--account**: Forge account name for execution mode

## Architecture

### Directory Structure
```
project-root/
├── action_runner.py          # Main entry point (in root)
├── python/
│   ├── vault_data/
│   │   ├── __init__.py
│   │   ├── base_vault.py         # Abstract base class
│   │   ├── registry.py           # Vault discovery system
│   │   └── vault_0x7f72...ae.py  # Vault-specific implementations
│   ├── utils/
│   │   ├── __init__.py
│   │   ├── web3_helper.py        # Web3 connection utilities
│   │   ├── encoding.py           # ABI encoding helpers
│   │   └── validation.py         # Input validation
│   └── README.md
├── requirements.txt
└── ... (other project files)
```

### Key Components

#### 1. BaseVault Abstract Class
Defines the interface that all vault implementations must follow:
- `get_deposit_data()`: Returns encoded deposit data
- `get_redeem_data(min_purchase_amount)`: Returns encoded redeem data
- `get_asset_decimals()`: Fetches token decimals from blockchain
- `scale_user_input()`: Converts human-readable amounts to wei

#### 2. Vault Registry
Automatically discovers and registers vault implementations based on filename patterns:
- Files named `vault_0x{address}.py` are automatically loaded
- Each vault class must inherit from `BaseVault`
- Runtime instantiation based on vault address

#### 3. Web3 Helper
Handles blockchain interactions:
- RPC connection management
- Contract calls for fetching decimals and other data
- Support for different networks (mainnet, polygon, etc.)

#### 4. Encoding Helper
Provides utilities for ABI encoding:
- Curve V2 trade data encoding
- Redeem parameters encoding
- Hex/bytes conversion utilities

## Adding New Vault Implementations

To add support for a new vault:

1. Create a new file: `vault_data/vault_0x{VAULT_ADDRESS}.py`
2. Implement a class that inherits from `BaseVault`
3. Override the required methods:

```python
from .base_vault import BaseVault
from ..utils.encoding import EncodingHelper

class Vault_0xYourVaultAddress(BaseVault):
    def get_deposit_data(self) -> bytes:
        # Return empty bytes if no special encoding needed
        return EncodingHelper.encode_empty_bytes()
    
    def get_redeem_data(self, min_purchase_amount: int) -> bytes:
        # Implement vault-specific redeem data encoding
        # Example for Curve V2:
        curve_data = EncodingHelper.encode_curve_v2_single_data(
            pool="0xYourPoolAddress",
            from_index=1,  # Context-dependent
            to_index=0     # Context-dependent
        )
        
        return EncodingHelper.encode_redeem_params(
            dex_id=7,  # CURVE_V2
            min_purchase_amount=min_purchase_amount,
            exchange_data=curve_data
        )
```

The registry will automatically discover and register your vault implementation.

## Migration from Shell Script

The Python action runner provides the same functionality as `createInitialPosition.sh` but with improvements:

### Old (Shell):
```bash
./createInitialPosition.sh sim 0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae 1000 2000 500 0x1234...
```

### New (Python):
```bash
python action_runner.py create-position sim 0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae 1000 2000 500 --sender 0x1234...
```

### Key Improvements:
- **Type Safety**: Input validation and proper error handling
- **Decimal Handling**: Automatic scaling based on token decimals
- **Extensibility**: Easy to add new vaults without modifying core logic
- **Better Error Messages**: Clear indication of what went wrong
- **Testability**: Each component can be unit tested
- **Cross-Platform**: Works on any system with Python

## Troubleshooting

### Common Issues

1. **"No vault implementation found"**: 
   - Check that a vault file exists for your address
   - Ensure the vault class inherits from `BaseVault`

2. **"Failed to connect to Web3 provider"**:
   - Verify your `MAINNET_RPC_URL` environment variable
   - Check that your RPC endpoint is accessible

3. **"Validation error"**:
   - Ensure addresses are properly formatted (0x prefix + 40 hex chars)
   - Check that amounts are valid positive numbers

4. **Forge execution fails**:
   - Ensure forge is installed and in your PATH
   - Verify your account setup for execution mode

### Debug Mode
Run with Python's verbose mode to see detailed error information:
```bash
python -v action_runner.py create-position ...
```

## Development

### Running Tests
```bash
# TODO: Add test suite
python -m pytest tests/
```

### Code Style
The codebase follows Python conventions:
- Type hints for better IDE support
- Docstrings for all public methods
- Clear separation of concerns
- Defensive programming practices

## Future Enhancements

Potential improvements for the system:
- Configuration files for vault-specific parameters
- Support for batch operations
- Integration with more DEX protocols
- Comprehensive test suite
- Logging and monitoring integration