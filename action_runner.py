#!/usr/bin/env python3
"""
Action Runner - Python replacement for createInitialPosition.sh

This script handles user input, processes vault-specific data encoding,
and executes Solidity action scripts via forge.
"""

import argparse
import os
import subprocess
import sys
from typing import Optional
from dotenv import load_dotenv

# Load .env file from the root directory
load_dotenv()

# Add the python directory to Python path for imports
python_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'python')
sys.path.insert(0, python_dir)

from utils.web3_helper import Web3Helper
from utils.validation import InputValidator, ValidationError
from utils.encoding import EncodingHelper
from vault_data.registry import VaultRegistry


class ActionRunner:
    """Main class for running vault actions."""
    
    def __init__(self):
        self.web3_helper = None
        self.vault_registry = VaultRegistry()
        self._setup_environment()
    
    def _setup_environment(self):
        """Setup environment variables and Web3 connection."""
        # Load environment variables
        self.etherscan_token = os.getenv('API_KEY_ETHERSCAN')
        self.rpc_url = os.getenv('MAINNET_RPC_URL') or os.getenv('RPC_URL')
        
        if not self.rpc_url:
            raise ValueError("MAINNET_RPC_URL or RPC_URL environment variable must be set")
        
        # Initialize Web3 helper
        try:
            self.web3_helper = Web3Helper(self.rpc_url)
        except Exception as e:
            print(f"Error: Failed to initialize Web3 connection: {e}")
            sys.exit(1)
    
    def create_initial_position(self, vault_address: str, vault_deposit_amount: str, 
                              morpho_supply_amount: str, morpho_borrow_amount: str,
                              min_purchase_amount: str, mode: str, 
                              sender_address: Optional[str] = None,
                              account_name: Optional[str] = None,
                              gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Supply to Morpho market and enter position on Notional vault."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            mode = InputValidator.validate_mode(mode)
            
            vault_deposit_integer = InputValidator.validate_integer_amount(vault_deposit_amount)
            morpho_supply_integer = InputValidator.validate_integer_amount(morpho_supply_amount)
            morpho_borrow_integer = InputValidator.validate_integer_amount(morpho_borrow_amount)
            min_purchase_integer = InputValidator.validate_integer_amount(min_purchase_amount)
            
            # Get vault implementation
            vault = self.vault_registry.create_vault(vault_address, self.web3_helper)
            if not vault:
                print(f"Error: No vault implementation found for address {vault_address}")
                print(f"Supported vaults: {self.vault_registry.list_supported_vaults()}")
                return False
            
            print(f"Using vault implementation for {vault_address}")
            
            # Define scaling for each input
            value_config = {
                'vault_deposit_amount': {'value': vault_deposit_integer, 'scale_type': 'asset'},
                'morpho_supply_amount': {'value': morpho_supply_integer, 'scale_type': 'asset'},
                'morpho_borrow_amount': {'value': morpho_borrow_integer, 'scale_type': 'asset'}
            }
            
            # Display and confirm values
            if not self._display_and_confirm_values(vault, value_config, mode):
                print("Transaction cancelled by user.")
                return False
            
            # Get deposit data
            deposit_data = vault.get_deposit_data(min_purchase_integer)
            deposit_data_hex = EncodingHelper.bytes_to_hex(deposit_data)
            
            print(f"Deposit data: {deposit_data_hex}")
            
            # Build forge command
            forge_cmd = self._build_initial_position_forge_command(
                action_script="script/actions/CreateInitialPosition.sol",
                vault_address=vault_address,
                initial_supply=morpho_supply_integer,
                initial_borrow=morpho_borrow_integer,
                initial_deposit=vault_deposit_integer,
                data=deposit_data_hex,
                mode=mode,
                sender_address=sender_address,
                account_name=account_name,
                gas_estimate_multiplier=gas_estimate_multiplier
            )
            
            # Execute forge command
            print("Executing forge command...")
            print(" ".join(forge_cmd))
            
            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url
            
            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                print("✓ Initial position created successfully!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False
                
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def exit_position_and_max_withdraw_from_morpho(self, vault_address: str, min_purchase_amount: str,
                                 mode: str, sender_address: Optional[str] = None,
                                 account_name: Optional[str] = None,
                                 gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Fully exits notional vault position and withdraws all supplied funds to the morpho market."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            mode = InputValidator.validate_mode(mode)
            min_purchase_integer = InputValidator.validate_integer_amount(min_purchase_amount)
            
            # Get vault implementation
            vault = self.vault_registry.create_vault(vault_address, self.web3_helper)
            if not vault:
                print(f"Error: No vault implementation found for address {vault_address}")
                return False
            
            # Get redeem data
            redeem_data = vault.get_redeem_data(min_purchase_integer)
            redeem_data_hex = EncodingHelper.bytes_to_hex(redeem_data)
            
            # Build and execute forge command
            forge_cmd = self._build_exit_forge_command(
                vault_address=vault_address,
                data=redeem_data_hex,
                mode=mode,
                sender_address=sender_address,
                account_name=account_name,
                gas_estimate_multiplier=gas_estimate_multiplier
            )
            
            print("Executing forge command...")
            
            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url
            
            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                print("✓ Position exited and withdrawn successfully!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False
                
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def exit_position(self, vault_address: str, shares_to_redeem: str, asset_to_repay: str,
                     min_purchase_amount: str, mode: str, sender_address: Optional[str] = None,
                     account_name: Optional[str] = None,
                     gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Executes an exit position action on a Notional vault."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            mode = InputValidator.validate_mode(mode)
            
            shares_to_redeem_integer = InputValidator.validate_integer_amount(shares_to_redeem)
            asset_to_repay_integer = InputValidator.validate_integer_amount(asset_to_repay)
            min_purchase_integer = InputValidator.validate_integer_amount(min_purchase_amount)
            
            # Get vault implementation
            vault = self.vault_registry.create_vault(vault_address, self.web3_helper)
            if not vault:
                print(f"Error: No vault implementation found for address {vault_address}")
                return False
            
            print(f"Exiting position for vault {vault_address}")
            
            # Define scaling for each input
            value_config = {
                'shares_to_redeem': {'value': shares_to_redeem_integer, 'scale_type': 'vault_share'},
                'asset_to_repay': {'value': asset_to_repay_integer, 'scale_type': 'asset'}
            }
            
            # Display and confirm values
            if not self._display_and_confirm_values(vault, value_config, mode):
                print("Transaction cancelled by user.")
                return False
            
            # Get redeem data
            redeem_data = vault.get_redeem_data(min_purchase_integer)
            redeem_data_hex = EncodingHelper.bytes_to_hex(redeem_data)
            
            print(f"Redeem data: {redeem_data_hex}")
            
            # Build and execute forge command
            forge_cmd = self._build_exit_position_forge_command(
                vault_address=vault_address,
                shares_to_redeem=shares_to_redeem_integer,
                asset_to_repay=asset_to_repay_integer,
                data=redeem_data_hex,
                mode=mode,
                sender_address=sender_address,
                account_name=account_name,
                gas_estimate_multiplier=gas_estimate_multiplier
            )
            
            print("Executing forge command...")
            
            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url
            
            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                print("✓ Position exited successfully!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False
                
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def redeem_vault_shares_to_max_leverage(self, vault_address: str, min_purchase_amount: str, mode: str,
                    sender_address: Optional[str] = None, account_name: Optional[str] = None,
                    gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Calculates amount of vault shares to redeem such that account is left at max leverage. Redeems shares and sends asset back to account."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            mode = InputValidator.validate_mode(mode)
            min_purchase_integer = InputValidator.validate_integer_amount(min_purchase_amount)
            
            # Get vault implementation
            vault = self.vault_registry.create_vault(vault_address, self.web3_helper)
            if not vault:
                print(f"Error: No vault implementation found for address {vault_address}")
                return False
            
            print(f"Calculating max leverage for vault {vault_address}")
            
            # No additional parameters to display for this action
            print(f"Calculating max leverage for vault {vault_address}")
            
            # Get redeem data
            redeem_data = vault.get_redeem_data(min_purchase_integer)
            redeem_data_hex = EncodingHelper.bytes_to_hex(redeem_data)
            
            print(f"Redeem data: {redeem_data_hex}")
            
            # Build and execute forge command
            forge_cmd = self._build_max_leverage_forge_command(
                vault_address=vault_address,
                data=redeem_data_hex,
                mode=mode,
                sender_address=sender_address,
                account_name=account_name,
                gas_estimate_multiplier=gas_estimate_multiplier
            )
            
            print("Executing forge command...")
            
            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url
            
            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                print("✓ Max leverage calculation completed successfully!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False
                
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def flash_liquidate(self, vault_address: str, liquidate_account: str, shares_to_liquidate: str, 
                       assets_to_borrow: str, min_purchase_amount: str, mode: str,
                       sender_address: Optional[str] = None, account_name: Optional[str] = None,
                       gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Execute FlashLiquidate action."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            liquidate_account = InputValidator.validate_address(liquidate_account)
            mode = InputValidator.validate_mode(mode)
            shares_to_liquidate_integer = InputValidator.validate_integer_amount(shares_to_liquidate)
            assets_to_borrow_integer = InputValidator.validate_integer_amount(assets_to_borrow)
            min_purchase_integer = InputValidator.validate_integer_amount(min_purchase_amount)
            
            # Get vault implementation
            vault = self.vault_registry.create_vault(vault_address, self.web3_helper)
            if not vault:
                print(f"Error: No vault implementation found for address {vault_address}")
                return False
            
            print(f"Performing flash liquidation for vault {vault_address}")
            print(f"Liquidating account: {liquidate_account}")
            
            # Define scaling for each input
            value_config = {
                'shares_to_liquidate': {'value': shares_to_liquidate_integer, 'scale_type': 'vault_share'},
                'assets_to_borrow': {'value': assets_to_borrow_integer, 'scale_type': 'asset'}
            }
            
            # Display and confirm values
            if not self._display_and_confirm_values(vault, value_config, mode):
                print("Transaction cancelled by user.")
                return False
            
            # Get redeem data
            redeem_data = vault.get_redeem_data(min_purchase_integer)
            redeem_data_hex = EncodingHelper.bytes_to_hex(redeem_data)
            
            print(f"Redeem data: {redeem_data_hex}")
            
            # Build and execute forge command
            forge_cmd = self._build_flash_liquidate_forge_command(
                vault_address=vault_address,
                liquidate_account=liquidate_account,
                shares_to_liquidate=str(shares_to_liquidate_integer),
                assets_to_borrow=str(assets_to_borrow_integer),
                data=redeem_data_hex,
                mode=mode,
                sender_address=sender_address,
                account_name=account_name,
                gas_estimate_multiplier=gas_estimate_multiplier
            )
            
            print("Executing forge command...")
            print(f"Command: {' '.join(forge_cmd)}")
            
            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url
            
            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                print("✓ Flash liquidation completed successfully!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False
                
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def view_market_details(self, vault_address: str,
                           sender_address: Optional[str] = None) -> bool:
        """Execute view market details query (simulation only)."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            
            print(f"Querying market details for vault {vault_address}")
            
            # Build and execute forge command (always in sim mode)
            forge_cmd = self._build_view_market_details_forge_command(
                vault_address=vault_address,
                sender_address=sender_address
            )
            
            print("Executing forge command...")
            
            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url
            
            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                print("✓ Market details query completed successfully!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False
                
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def view_account_details(self, vault_address: str, account_address: str,
                            sender_address: Optional[str] = None) -> bool:
        """Execute view account details query (simulation only)."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            account_address = InputValidator.validate_address(account_address)
            
            print(f"Querying account details for account {account_address} in vault {vault_address}")
            
            # Build and execute forge command (always in sim mode)
            forge_cmd = self._build_view_account_details_forge_command(
                vault_address=vault_address,
                account_address=account_address,
                sender_address=sender_address
            )
            
            print("Executing forge command...")
            
            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url
            
            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                print("✓ Account details query completed successfully!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False
                
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def get_decimals(self, vault_address: str) -> bool:
        """Get and display decimal information for a vault."""
        try:
            # Validate input
            vault_address = InputValidator.validate_address(vault_address)
            
            print(f"Getting decimal information for vault: {vault_address}")
            
            # Get vault instance
            vault = self.vault_registry.create_vault(vault_address, self.web3_helper)
            
            if not vault:
                print(f"Error: No vault implementation found for address {vault_address}")
                return False
            
            print(f"Using vault implementation for {vault_address}")
            
            # Get decimals
            asset_decimals, yield_token_decimals, vault_share_decimals = vault.get_decimals()
            
            print("=" * 60)
            print(f"VAULT DECIMAL INFORMATION")
            print("=" * 60)
            print(f"Vault Address:        {vault_address}")
            print(f"Asset Decimals:       {asset_decimals}")
            print(f"Yield Token Decimals: {yield_token_decimals}")
            print(f"Vault Share Decimals: {vault_share_decimals}")
            print("=" * 60)
            
            return True
            
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def withdraw_from_morpho(self, vault_address: str, shares_amount: str, mode: str,
                           sender_address: Optional[str] = None,
                           account_name: Optional[str] = None,
                           gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Execute WithdrawFromMorpho action."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            mode = InputValidator.validate_mode(mode)
            shares_amount_integer = InputValidator.validate_integer_amount(shares_amount)
            
            print(f"Withdrawing from Morpho for vault {vault_address}")
            print(f"Shares amount: {shares_amount_integer}")
            
            # Build and execute forge command
            forge_cmd = self._build_morpho_withdraw_forge_command(
                vault_address=vault_address,
                shares_amount=shares_amount_integer,
                mode=mode,
                sender_address=sender_address,
                account_name=account_name,
                gas_estimate_multiplier=gas_estimate_multiplier
            )
            
            print("Executing forge command...")
            
            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url
            
            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                print("✓ Successfully withdrew from Morpho!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False
                
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def deposit_to_morpho(self, vault_address: str, asset_amount: str, mode: str,
                        sender_address: Optional[str] = None,
                        account_name: Optional[str] = None,
                        gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Execute DepositToMorpho action."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            mode = InputValidator.validate_mode(mode)
            asset_amount_integer = InputValidator.validate_integer_amount(asset_amount)

            print(f"Depositing to Morpho for vault {vault_address}")
            print(f"Asset amount: {asset_amount_integer}")

            # Build and execute forge command
            forge_cmd = self._build_deposit_to_morpho_forge_command(
                vault_address=vault_address,
                asset_amount=asset_amount_integer,
                mode=mode,
                sender_address=sender_address,
                account_name=account_name,
                gas_estimate_multiplier=gas_estimate_multiplier
            )

            print("Executing forge command...")

            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url

            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)

            if result.returncode == 0:
                print("✓ Successfully deposited to Morpho!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False

        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False

    def initiate_withdraw(self, vault_address: str, mode: str,
                        sender_address: Optional[str] = None,
                        account_name: Optional[str] = None,
                        gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Execute InitiateWithdraw action."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            mode = InputValidator.validate_mode(mode)
            
            # Get vault implementation
            vault = self.vault_registry.create_vault(vault_address, self.web3_helper)
            if not vault:
                print(f"Error: No vault implementation found for address {vault_address}")
                return False
            
            print(f"Initiating withdraw for vault {vault_address}")
            
            # Get withdraw data
            withdraw_data = vault.get_withdraw_data()
            withdraw_data_hex = EncodingHelper.bytes_to_hex(withdraw_data)
            
            print(f"Withdraw data: {withdraw_data_hex}")
            
            # Build and execute forge command
            forge_cmd = self._build_initiate_withdraw_forge_command(
                vault_address=vault_address,
                data=withdraw_data_hex,
                mode=mode,
                sender_address=sender_address,
                account_name=account_name,
                gas_estimate_multiplier=gas_estimate_multiplier
            )
            
            print("Executing forge command...")
            
            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url
            
            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                print("✓ Withdraw initiated successfully!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False
                
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def force_withdraw(self, vault_address: str, account_address: str, mode: str,
                      sender_address: Optional[str] = None,
                      account_name: Optional[str] = None,
                      gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Execute ForceWithdraw action."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            account_address = InputValidator.validate_address(account_address)
            mode = InputValidator.validate_mode(mode)
            
            # Get vault implementation
            vault = self.vault_registry.create_vault(vault_address, self.web3_helper)
            if not vault:
                print(f"Error: No vault implementation found for address {vault_address}")
                return False
            
            print(f"Initiating force withdraw for vault {vault_address}")
            print(f"Account: {account_address}")
            
            # Get withdraw data
            withdraw_data = vault.get_withdraw_data()
            withdraw_data_hex = EncodingHelper.bytes_to_hex(withdraw_data)
            
            print(f"Withdraw data: {withdraw_data_hex}")
            
            # Build and execute forge command
            forge_cmd = self._build_force_withdraw_forge_command(
                vault_address=vault_address,
                account_address=account_address,
                data=withdraw_data_hex,
                mode=mode,
                sender_address=sender_address,
                account_name=account_name,
                gas_estimate_multiplier=gas_estimate_multiplier
            )
            
            print("Executing forge command...")
            
            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url
            
            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                print("✓ Force withdraw completed successfully!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False
                
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def finalize_withdraw(self, vault_address: str, account_address: str, wrm_address: str, mode: str,
                         sender_address: Optional[str] = None,
                         account_name: Optional[str] = None,
                         gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Execute FinalizeWithdraw action."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            account_address = InputValidator.validate_address(account_address)
            wrm_address = InputValidator.validate_address(wrm_address)
            mode = InputValidator.validate_mode(mode)
            
            print(f"Finalizing withdraw for vault {vault_address}")
            print(f"Account: {account_address}")
            print(f"WRM: {wrm_address}")
            
            # Build and execute forge command
            forge_cmd = self._build_finalize_withdraw_forge_command(
                vault_address=vault_address,
                account_address=account_address,
                wrm_address=wrm_address,
                mode=mode,
                sender_address=sender_address,
                account_name=account_name,
                gas_estimate_multiplier=gas_estimate_multiplier
            )
            
            print("Executing forge command...")
            
            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url
            
            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                print("✓ Finalize withdraw completed successfully!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False
                
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def liquidate(self, vault_address: str, liquidate_account: str, shares_to_liquidate: str, mode: str,
                 sender_address: Optional[str] = None,
                 account_name: Optional[str] = None,
                 gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Execute Liquidate action."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            liquidate_account = InputValidator.validate_address(liquidate_account)
            mode = InputValidator.validate_mode(mode)
            shares_to_liquidate_integer = InputValidator.validate_integer_amount(shares_to_liquidate)
            
            # Get vault implementation for display purposes
            vault = self.vault_registry.create_vault(vault_address, self.web3_helper)
            if not vault:
                print(f"Error: No vault implementation found for address {vault_address}")
                return False
            
            print(f"Performing liquidation for vault {vault_address}")
            print(f"Liquidating account: {liquidate_account}")
            
            # Define scaling for display
            value_config = {
                'shares_to_liquidate': {'value': shares_to_liquidate_integer, 'scale_type': 'vault_share'}
            }
            
            # Display and confirm values
            if not self._display_and_confirm_values(vault, value_config, mode):
                print("Transaction cancelled by user.")
                return False
            
            # Build and execute forge command
            forge_cmd = self._build_liquidate_forge_command(
                vault_address=vault_address,
                liquidate_account=liquidate_account,
                shares_to_liquidate=str(shares_to_liquidate_integer),
                mode=mode,
                sender_address=sender_address,
                account_name=account_name,
                gas_estimate_multiplier=gas_estimate_multiplier
            )
            
            print("Executing forge command...")
            
            # Set environment variables for forge
            env = os.environ.copy()
            if self.etherscan_token:
                env['ETHERSCAN_TOKEN'] = self.etherscan_token
            if self.rpc_url:
                env['RPC_URL'] = self.rpc_url
            
            result = subprocess.run(forge_cmd, capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                print("✓ Liquidation completed successfully!")
                print(result.stdout)
                return True
            else:
                print("✗ Error executing forge command:")
                print("STDOUT:", result.stdout)
                print("STDERR:", result.stderr)
                return False
                
        except ValidationError as e:
            print(f"Validation error: {e}")
            return False
        except Exception as e:
            print(f"Unexpected error: {e}")
            return False
    
    def _build_initial_position_forge_command(self, action_script: str, vault_address: str,
                           initial_supply: int, initial_borrow: int,
                           initial_deposit: int, data: str, mode: str,
                           sender_address: Optional[str] = None,
                           account_name: Optional[str] = None,
                           gas_estimate_multiplier: Optional[int] = None) -> list[str]:
        """Build forge command arguments."""
        cmd = [
            "forge", "script", action_script,
            "--sig", "run(address,uint256,uint256,uint256,bytes)"
        ]
        
        if mode == "sim":
            cmd.extend(["--fork-url", self.rpc_url])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        elif mode == "exec":
            cmd.extend(["--rpc-url", self.rpc_url, "--broadcast"])
            if account_name:
                cmd.extend(["--account", account_name])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        
        # Add gas estimate multiplier if provided
        if gas_estimate_multiplier:
            cmd.extend(["--gas-estimate-multiplier", str(gas_estimate_multiplier)])
        
        # Add function arguments
        cmd.extend([
            vault_address,
            str(initial_supply),
            str(initial_borrow),
            str(initial_deposit),
            data
        ])
        
        return cmd
    
    def _build_exit_forge_command(self, vault_address: str, data: str, mode: str,
                                sender_address: Optional[str] = None,
                                account_name: Optional[str] = None,
                                gas_estimate_multiplier: Optional[int] = None) -> list[str]:
        """Build forge command arguments for exit position."""
        cmd = [
            "forge", "script", "script/actions/ExitPositionAndWithdraw.sol",
            "--sig", "run(address,bytes)"
        ]
        
        if mode == "sim":
            cmd.extend(["--fork-url", self.rpc_url])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        elif mode == "exec":
            cmd.extend(["--rpc-url", self.rpc_url, "--broadcast"])
            if account_name:
                cmd.extend(["--account", account_name])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        
        # Add gas estimate multiplier if provided
        if gas_estimate_multiplier:
            cmd.extend(["--gas-estimate-multiplier", str(gas_estimate_multiplier)])
        
        # Add function arguments
        cmd.extend([
            vault_address,
            data
        ])
        
        return cmd
    
    def _build_morpho_withdraw_forge_command(self, vault_address: str, shares_amount: int, mode: str,
                                           sender_address: Optional[str] = None,
                                           account_name: Optional[str] = None,
                                           gas_estimate_multiplier: Optional[int] = None) -> list[str]:
        """Build forge command arguments for Morpho withdraw."""
        cmd = [
            "forge", "script", "script/actions/WithdrawFromMorpho.sol",
            "--sig", "run(address,uint256)"
        ]
        
        if mode == "sim":
            cmd.extend(["--fork-url", self.rpc_url])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        elif mode == "exec":
            cmd.extend(["--rpc-url", self.rpc_url, "--broadcast"])
            if account_name:
                cmd.extend(["--account", account_name])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        
        # Add gas estimate multiplier if provided
        if gas_estimate_multiplier:
            cmd.extend(["--gas-estimate-multiplier", str(gas_estimate_multiplier)])
        
        # Add function arguments
        cmd.extend([
            vault_address,
            str(shares_amount)
        ])
        
        return cmd
    
    def _build_deposit_to_morpho_forge_command(self, vault_address: str, asset_amount: int, mode: str,
                                             sender_address: Optional[str] = None,
                                             account_name: Optional[str] = None,
                                             gas_estimate_multiplier: Optional[int] = None) -> list[str]:
        """Build forge command arguments for Morpho deposit."""
        cmd = [
            "forge", "script", "script/actions/DepositToMorpho.sol",
            "--sig", "run(address,uint256)"
        ]

        if mode == "sim":
            cmd.extend(["--fork-url", self.rpc_url])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        elif mode == "exec":
            cmd.extend(["--rpc-url", self.rpc_url, "--broadcast"])
            if account_name:
                cmd.extend(["--account", account_name])
            if sender_address:
                cmd.extend(["--sender", sender_address])

        # Add gas estimate multiplier if provided
        if gas_estimate_multiplier:
            cmd.extend(["--gas-estimate-multiplier", str(gas_estimate_multiplier)])

        # Add function arguments
        cmd.extend([
            vault_address,
            str(asset_amount)
        ])

        return cmd

    def _build_initiate_withdraw_forge_command(self, vault_address: str, data: str, mode: str,
                                             sender_address: Optional[str] = None,
                                             account_name: Optional[str] = None,
                                             gas_estimate_multiplier: Optional[int] = None) -> list[str]:
        """Build forge command arguments for initiate withdraw."""
        cmd = [
            "forge", "script", "script/actions/InitiateWithdraw.sol",
            "--sig", "run(address,bytes)"
        ]
        
        if mode == "sim":
            cmd.extend(["--fork-url", self.rpc_url])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        elif mode == "exec":
            cmd.extend(["--rpc-url", self.rpc_url, "--broadcast"])
            if account_name:
                cmd.extend(["--account", account_name])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        
        # Add gas estimate multiplier if provided
        if gas_estimate_multiplier:
            cmd.extend(["--gas-estimate-multiplier", str(gas_estimate_multiplier)])
        
        # Add function arguments
        cmd.extend([
            vault_address,
            data
        ])
        
        return cmd
    
    def _build_exit_position_forge_command(self, vault_address: str, shares_to_redeem: int, 
                                         asset_to_repay: int, data: str, mode: str,
                                         sender_address: Optional[str] = None,
                                         account_name: Optional[str] = None,
                                         gas_estimate_multiplier: Optional[int] = None) -> list[str]:
        """Build forge command arguments for exit position."""
        cmd = [
            "forge", "script", "script/actions/ExitPosition.sol",
            "--sig", "run(address,uint256,uint256,bytes)"
        ]
        
        if mode == "sim":
            cmd.extend(["--fork-url", self.rpc_url])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        elif mode == "exec":
            cmd.extend(["--rpc-url", self.rpc_url, "--broadcast"])
            if account_name:
                cmd.extend(["--account", account_name])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        
        # Add gas estimate multiplier if provided
        if gas_estimate_multiplier:
            cmd.extend(["--gas-estimate-multiplier", str(gas_estimate_multiplier)])
        
        # Add function arguments
        cmd.extend([
            vault_address,
            str(shares_to_redeem),
            str(asset_to_repay),
            data
        ])
        
        return cmd
    
    def _build_max_leverage_forge_command(self, vault_address: str, data: str, mode: str,
                                        sender_address: Optional[str] = None,
                                        account_name: Optional[str] = None,
                                        gas_estimate_multiplier: Optional[int] = None) -> list[str]:
        """Build forge command arguments for max leverage calculation."""
        cmd = [
            "forge", "script", "script/actions/MaxLeverage.sol",
            "--sig", "run(address,bytes)"
        ]
        
        if mode == "sim":
            cmd.extend(["--fork-url", self.rpc_url])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        elif mode == "exec":
            cmd.extend(["--rpc-url", self.rpc_url, "--broadcast"])
            if account_name:
                cmd.extend(["--account", account_name])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        
        # Add gas estimate multiplier if provided
        if gas_estimate_multiplier:
            cmd.extend(["--gas-estimate-multiplier", str(gas_estimate_multiplier)])
        
        # Add function arguments
        cmd.extend([
            vault_address,
            data
        ])
        
        return cmd
    
    def _build_flash_liquidate_forge_command(self, vault_address: str, liquidate_account: str, 
                                           shares_to_liquidate: str, assets_to_borrow: str, data: str, mode: str,
                                           sender_address: Optional[str] = None,
                                           account_name: Optional[str] = None,
                                           gas_estimate_multiplier: Optional[int] = None) -> list[str]:
        """Build forge command arguments for flash liquidate."""
        cmd = [
            "forge", "script", "script/actions/FlashLiquidate.sol",
            "--sig", "run(address,address,uint256,uint256,bytes)"
        ]
        
        if mode == "sim":
            cmd.extend(["--fork-url", self.rpc_url])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        elif mode == "exec":
            cmd.extend(["--rpc-url", self.rpc_url, "--broadcast"])
            if account_name:
                cmd.extend(["--account", account_name])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        
        # Add gas estimate multiplier if provided
        if gas_estimate_multiplier:
            cmd.extend(["--gas-estimate-multiplier", str(gas_estimate_multiplier)])
        
        # Add function arguments
        cmd.extend([
            vault_address,
            liquidate_account,
            shares_to_liquidate,
            assets_to_borrow,
            data
        ])
        
        return cmd
    
    def _display_and_confirm_values(self, vault, value_config: dict, mode: str) -> bool:
        """Display human-readable values and confirm with user for exec mode."""
        try:
            # Get decimals from vault
            asset_decimals, yield_token_decimals, vault_share_decimals = vault.get_decimals()
            
            # Map scale types to actual decimals
            scale_map = {
                'asset': asset_decimals,
                'vault_share': vault_share_decimals, 
                'yield_token': yield_token_decimals
            }
            
            # Display formatted table
            print("=" * 60)
            print("TRANSACTION PARAMETERS IN HUMAN READABLE PRECISION")
            print("=" * 60)
            for name, config in value_config.items():
                decimals = scale_map[config['scale_type']]
                human_value = config['value'] / (10 ** decimals)
                print(f"{name.replace('_', ' ').title():30} {human_value:>20.6f}")
            print("=" * 60)
            
            # Confirmation prompt for exec mode
            if mode == 'exec':
                response = input("Proceed with these values? (y/N): ").strip().lower()
                return response == 'y'
            
            return True
            
        except Exception as e:
            print(f"Error displaying values: {e}")
            return False
    
    def _build_view_market_details_forge_command(self, vault_address: str,
                                               sender_address: Optional[str] = None) -> list[str]:
        """Build forge command arguments for view market details."""
        cmd = [
            "forge", "script", "script/actions/Views.sol",
            "--sig", "getMarketDetails(address)",
            "--fork-url", self.rpc_url
        ]
        
        if sender_address:
            cmd.extend(["--sender", sender_address])
        
        # Add function arguments
        cmd.extend([vault_address])
        
        return cmd
    
    def _build_view_account_details_forge_command(self, vault_address: str, account_address: str,
                                                 sender_address: Optional[str] = None) -> list[str]:
        """Build forge command arguments for view account details."""
        cmd = [
            "forge", "script", "script/actions/Views.sol",
            "--sig", "getAccountDetails(address,address)",
            "--fork-url", self.rpc_url
        ]
        
        if sender_address:
            cmd.extend(["--sender", sender_address])
        
        # Add function arguments
        cmd.extend([vault_address, account_address])
        
        return cmd
    
    def _build_force_withdraw_forge_command(self, vault_address: str, account_address: str, data: str, mode: str,
                                          sender_address: Optional[str] = None,
                                          account_name: Optional[str] = None,
                                          gas_estimate_multiplier: Optional[int] = None) -> list[str]:
        """Build forge command arguments for force withdraw."""
        cmd = [
            "forge", "script", "script/actions/ForceWithdraw.sol",
            "--sig", "run(address,address,bytes)"
        ]
        
        if mode == "sim":
            cmd.extend(["--fork-url", self.rpc_url])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        elif mode == "exec":
            cmd.extend(["--rpc-url", self.rpc_url, "--broadcast"])
            if account_name:
                cmd.extend(["--account", account_name])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        
        # Add gas estimate multiplier if provided
        if gas_estimate_multiplier:
            cmd.extend(["--gas-estimate-multiplier", str(gas_estimate_multiplier)])
        
        # Add function arguments
        cmd.extend([
            account_address,
            vault_address,
            data
        ])
        
        return cmd
    
    def _build_finalize_withdraw_forge_command(self, vault_address: str, account_address: str, wrm_address: str, mode: str,
                                             sender_address: Optional[str] = None,
                                             account_name: Optional[str] = None,
                                             gas_estimate_multiplier: Optional[int] = None) -> list[str]:
        """Build forge command arguments for finalize withdraw."""
        cmd = [
            "forge", "script", "script/actions/FinalizeWithdraw.sol",
            "--sig", "run(address,address,address)"
        ]
        
        if mode == "sim":
            cmd.extend(["--fork-url", self.rpc_url])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        elif mode == "exec":
            cmd.extend(["--rpc-url", self.rpc_url, "--broadcast"])
            if account_name:
                cmd.extend(["--account", account_name])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        
        # Add gas estimate multiplier if provided
        if gas_estimate_multiplier:
            cmd.extend(["--gas-estimate-multiplier", str(gas_estimate_multiplier)])
        
        # Add function arguments
        cmd.extend([
            account_address,
            vault_address,
            wrm_address
        ])
        
        return cmd
    
    def _build_liquidate_forge_command(self, vault_address: str, liquidate_account: str, shares_to_liquidate: str, mode: str,
                                     sender_address: Optional[str] = None,
                                     account_name: Optional[str] = None,
                                     gas_estimate_multiplier: Optional[int] = None) -> list[str]:
        """Build forge command arguments for liquidate."""
        cmd = [
            "forge", "script", "script/actions/Liquidate.sol",
            "--sig", "run(address,address,uint256)"
        ]
        
        if mode == "sim":
            cmd.extend(["--fork-url", self.rpc_url])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        elif mode == "exec":
            cmd.extend(["--rpc-url", self.rpc_url, "--broadcast"])
            if account_name:
                cmd.extend(["--account", account_name])
            if sender_address:
                cmd.extend(["--sender", sender_address])
        
        # Add gas estimate multiplier if provided
        if gas_estimate_multiplier:
            cmd.extend(["--gas-estimate-multiplier", str(gas_estimate_multiplier)])
        
        # Add function arguments
        cmd.extend([
            vault_address,
            liquidate_account,
            shares_to_liquidate
        ])
        
        return cmd


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Python-based action runner for vault operations")
    
    subparsers = parser.add_subparsers(dest='action', help='Action to perform')
    
    # Create initial position command
    create_parser = subparsers.add_parser('create-position', help='Create initial position')
    create_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    create_parser.add_argument('vault_address', help='Vault contract address')
    create_parser.add_argument('vault_deposit_amount', help='Vault deposit amount')
    create_parser.add_argument('morpho_supply_amount', help='Morpho supply amount')
    create_parser.add_argument('morpho_borrow_amount', help='Morpho borrow amount')
    create_parser.add_argument('min_purchase_amount', help='Minimum purchase amount for slippage protection')
    create_parser.add_argument('--sender', help='Sender address (for sim mode)')
    create_parser.add_argument('--account', help='Account name (for exec mode)')
    create_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')
    
    # Exit position and withdraw command
    exit_and_withdraw_parser = subparsers.add_parser('exit-position-and-max-withdraw-from-morpho', help='Fully exits notional vault position and withdraws all supplied funds to the morpho market')
    exit_and_withdraw_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    exit_and_withdraw_parser.add_argument('vault_address', help='Vault contract address')
    exit_and_withdraw_parser.add_argument('min_purchase_amount', help='Minimum purchase amount')
    exit_and_withdraw_parser.add_argument('--sender', help='Sender address (for sim mode)')
    exit_and_withdraw_parser.add_argument('--account', help='Account name (for exec mode)')
    exit_and_withdraw_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')
    
    # Exit position command
    exit_parser = subparsers.add_parser('exit-position', help='Exit position with specified shares and asset amounts')
    exit_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    exit_parser.add_argument('vault_address', help='Vault contract address')
    exit_parser.add_argument('shares_to_redeem', help='Shares to redeem (1e24 precision)')
    exit_parser.add_argument('asset_to_repay', help='Asset amount to repay (native precision)')
    exit_parser.add_argument('min_purchase_amount', help='Minimum purchase amount for slippage protection')
    exit_parser.add_argument('--sender', help='Sender address (for sim mode)')
    exit_parser.add_argument('--account', help='Account name (for exec mode)')
    exit_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')
    
    # Withdraw from Morpho command
    morpho_parser = subparsers.add_parser('withdraw-from-morpho', help='Withdraw assets from Morpho market')
    morpho_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    morpho_parser.add_argument('vault_address', help='Vault contract address')
    morpho_parser.add_argument('shares_amount', help='Shares amount to withdraw (integer, pre-scaled)')
    morpho_parser.add_argument('--sender', help='Sender address (for sim mode)')
    morpho_parser.add_argument('--account', help='Account name (for exec mode)')
    morpho_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')

    # Deposit to Morpho command
    deposit_morpho_parser = subparsers.add_parser('deposit-to-morpho', help='Deposit assets to Morpho market')
    deposit_morpho_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    deposit_morpho_parser.add_argument('vault_address', help='Vault contract address')
    deposit_morpho_parser.add_argument('asset_amount', help='Asset amount to deposit (integer, pre-scaled)')
    deposit_morpho_parser.add_argument('--sender', help='Sender address (for sim mode)')
    deposit_morpho_parser.add_argument('--account', help='Account name (for exec mode)')
    deposit_morpho_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')

    # Initiate withdraw command
    initiate_parser = subparsers.add_parser('initiate-withdraw', help='Initiate withdraw request for vault assets')
    initiate_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    initiate_parser.add_argument('vault_address', help='Vault contract address')
    initiate_parser.add_argument('--sender', help='Sender address (for sim mode)')
    initiate_parser.add_argument('--account', help='Account name (for exec mode)')
    initiate_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')
    
    # Max leverage command
    max_leverage_parser = subparsers.add_parser('redeem-vault-shares-to-max-leverage', help='Calculates amount of vault shares to redeem such that account is left at max leverage. Redeems shares and sends asset back to account')
    max_leverage_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    max_leverage_parser.add_argument('vault_address', help='Vault contract address')
    max_leverage_parser.add_argument('min_purchase_amount', help='Minimum purchase amount for slippage protection')
    max_leverage_parser.add_argument('--sender', help='Sender address (for sim mode)')
    max_leverage_parser.add_argument('--account', help='Account name (for exec mode)')
    max_leverage_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')
    
    # Flash liquidate command
    flash_liquidate_parser = subparsers.add_parser('flash-liquidate', help='Perform flash liquidation of an account')
    flash_liquidate_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    flash_liquidate_parser.add_argument('vault_address', help='Vault contract address')
    flash_liquidate_parser.add_argument('liquidate_account', help='Account to liquidate')
    flash_liquidate_parser.add_argument('shares_to_liquidate', help='Shares to liquidate (1e24 precision)')
    flash_liquidate_parser.add_argument('assets_to_borrow', help='Assets to borrow for flash loan')
    flash_liquidate_parser.add_argument('min_purchase_amount', help='Minimum purchase amount for slippage protection')
    flash_liquidate_parser.add_argument('--sender', help='Sender address (for sim mode)')
    flash_liquidate_parser.add_argument('--account', help='Account name (for exec mode)')
    flash_liquidate_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')
    
    # View market details command (simulation only)
    view_market_parser = subparsers.add_parser('view-market-details', help='View market details for a vault (simulation only)')
    view_market_parser.add_argument('vault_address', help='Vault contract address')
    view_market_parser.add_argument('--sender', help='Sender address (optional)')
    
    # View account details command (simulation only)
    view_account_parser = subparsers.add_parser('view-account-details', help='View account details for a vault (simulation only)')
    view_account_parser.add_argument('vault_address', help='Vault contract address')
    view_account_parser.add_argument('account_address', help='Account address to query')
    view_account_parser.add_argument('--sender', help='Sender address (optional)')
    
    # Get decimals command
    decimals_parser = subparsers.add_parser('get-decimals', help='Get decimal information for a vault')
    decimals_parser.add_argument('vault_address', help='Vault contract address')
    
    # Force withdraw command
    force_withdraw_parser = subparsers.add_parser('force-withdraw', help='Execute force withdraw for an account')
    force_withdraw_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    force_withdraw_parser.add_argument('vault_address', help='Vault contract address')
    force_withdraw_parser.add_argument('account_address', help='Account address to force withdraw')
    force_withdraw_parser.add_argument('--sender', help='Sender address (for sim mode)')
    force_withdraw_parser.add_argument('--account', help='Account name (for exec mode)')
    force_withdraw_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')
    
    # Finalize withdraw command
    finalize_withdraw_parser = subparsers.add_parser('finalize-withdraw', help='Finalize withdraw request for an account')
    finalize_withdraw_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    finalize_withdraw_parser.add_argument('vault_address', help='Vault contract address')
    finalize_withdraw_parser.add_argument('account_address', help='Account address to finalize withdraw')
    finalize_withdraw_parser.add_argument('wrm_address', help='Withdraw Request Manager contract address')
    finalize_withdraw_parser.add_argument('--sender', help='Sender address (for sim mode)')
    finalize_withdraw_parser.add_argument('--account', help='Account name (for exec mode)')
    finalize_withdraw_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')
    
    # Liquidate command
    liquidate_parser = subparsers.add_parser('liquidate', help='Liquidate an account position')
    liquidate_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    liquidate_parser.add_argument('vault_address', help='Vault contract address')
    liquidate_parser.add_argument('liquidate_account', help='Account address to liquidate')
    liquidate_parser.add_argument('shares_to_liquidate', help='Shares to liquidate (1e24 precision)')
    liquidate_parser.add_argument('--sender', help='Sender address (for sim mode)')
    liquidate_parser.add_argument('--account', help='Account name (for exec mode)')
    liquidate_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')
    
    # List vaults command
    subparsers.add_parser('list-vaults', help='List supported vault addresses')
    
    args = parser.parse_args()
    
    if not args.action:
        parser.print_help()
        sys.exit(1)
    
    try:
        runner = ActionRunner()
        
        if args.action == 'create-position':
            if args.mode == 'sim' and not args.sender:
                print("Error: --sender is required for sim mode")
                sys.exit(1)
            if args.mode == 'exec' and not args.account:
                print("Error: --account is required for exec mode")
                sys.exit(1)
            
            success = runner.create_initial_position(
                vault_address=args.vault_address,
                vault_deposit_amount=args.vault_deposit_amount,
                morpho_supply_amount=args.morpho_supply_amount,
                morpho_borrow_amount=args.morpho_borrow_amount,
                min_purchase_amount=args.min_purchase_amount,
                mode=args.mode,
                sender_address=args.sender,
                account_name=args.account,
                gas_estimate_multiplier=args.gas_estimate_multiplier
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'exit-position-and-max-withdraw-from-morpho':
            if args.mode == 'sim' and not args.sender:
                print("Error: --sender is required for sim mode")
                sys.exit(1)
            if args.mode == 'exec' and not args.account:
                print("Error: --account is required for exec mode")
                sys.exit(1)
            
            success = runner.exit_position_and_max_withdraw_from_morpho(
                vault_address=args.vault_address,
                min_purchase_amount=args.min_purchase_amount,
                mode=args.mode,
                sender_address=args.sender,
                account_name=args.account,
                gas_estimate_multiplier=args.gas_estimate_multiplier
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'exit-position':
            if args.mode == 'sim' and not args.sender:
                print("Error: --sender is required for sim mode")
                sys.exit(1)
            if args.mode == 'exec' and not args.account:
                print("Error: --account is required for exec mode")
                sys.exit(1)
            
            success = runner.exit_position(
                vault_address=args.vault_address,
                shares_to_redeem=args.shares_to_redeem,
                asset_to_repay=args.asset_to_repay,
                min_purchase_amount=args.min_purchase_amount,
                mode=args.mode,
                sender_address=args.sender,
                account_name=args.account,
                gas_estimate_multiplier=args.gas_estimate_multiplier
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'withdraw-from-morpho':
            if args.mode == 'sim' and not args.sender:
                print("Error: --sender is required for sim mode")
                sys.exit(1)
            if args.mode == 'exec' and not args.account:
                print("Error: --account is required for exec mode")
                sys.exit(1)

            success = runner.withdraw_from_morpho(
                vault_address=args.vault_address,
                shares_amount=args.shares_amount,
                mode=args.mode,
                sender_address=args.sender,
                account_name=args.account,
                gas_estimate_multiplier=args.gas_estimate_multiplier
            )
            sys.exit(0 if success else 1)

        elif args.action == 'deposit-to-morpho':
            if args.mode == 'sim' and not args.sender:
                print("Error: --sender is required for sim mode")
                sys.exit(1)
            if args.mode == 'exec' and not args.account:
                print("Error: --account is required for exec mode")
                sys.exit(1)

            success = runner.deposit_to_morpho(
                vault_address=args.vault_address,
                asset_amount=args.asset_amount,
                mode=args.mode,
                sender_address=args.sender,
                account_name=args.account,
                gas_estimate_multiplier=args.gas_estimate_multiplier
            )
            sys.exit(0 if success else 1)

        elif args.action == 'initiate-withdraw':
            if args.mode == 'sim' and not args.sender:
                print("Error: --sender is required for sim mode")
                sys.exit(1)
            if args.mode == 'exec' and not args.account:
                print("Error: --account is required for exec mode")
                sys.exit(1)
            
            success = runner.initiate_withdraw(
                vault_address=args.vault_address,
                mode=args.mode,
                sender_address=args.sender,
                account_name=args.account,
                gas_estimate_multiplier=args.gas_estimate_multiplier
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'redeem-vault-shares-to-max-leverage':
            if args.mode == 'sim' and not args.sender:
                print("Error: --sender is required for sim mode")
                sys.exit(1)
            if args.mode == 'exec' and not args.account:
                print("Error: --account is required for exec mode")
                sys.exit(1)
            
            success = runner.redeem_vault_shares_to_max_leverage(
                vault_address=args.vault_address,
                min_purchase_amount=args.min_purchase_amount,
                mode=args.mode,
                sender_address=args.sender,
                account_name=args.account,
                gas_estimate_multiplier=args.gas_estimate_multiplier
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'flash-liquidate':
            if args.mode == 'sim' and not args.sender:
                print("Error: --sender is required for sim mode")
                sys.exit(1)
            if args.mode == 'exec' and not args.account:
                print("Error: --account is required for exec mode")
                sys.exit(1)
            
            success = runner.flash_liquidate(
                vault_address=args.vault_address,
                liquidate_account=args.liquidate_account,
                shares_to_liquidate=args.shares_to_liquidate,
                assets_to_borrow=args.assets_to_borrow,
                min_purchase_amount=args.min_purchase_amount,
                mode=args.mode,
                sender_address=args.sender,
                account_name=args.account,
                gas_estimate_multiplier=args.gas_estimate_multiplier
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'view-market-details':
            success = runner.view_market_details(
                vault_address=args.vault_address,
                sender_address=args.sender
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'view-account-details':
            success = runner.view_account_details(
                vault_address=args.vault_address,
                account_address=args.account_address,
                sender_address=args.sender
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'get-decimals':
            success = runner.get_decimals(
                vault_address=args.vault_address
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'force-withdraw':
            if args.mode == 'sim' and not args.sender:
                print("Error: --sender is required for sim mode")
                sys.exit(1)
            if args.mode == 'exec' and not args.account:
                print("Error: --account is required for exec mode")
                sys.exit(1)
            
            success = runner.force_withdraw(
                vault_address=args.vault_address,
                account_address=args.account_address,
                mode=args.mode,
                sender_address=args.sender,
                account_name=args.account,
                gas_estimate_multiplier=args.gas_estimate_multiplier
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'finalize-withdraw':
            if args.mode == 'sim' and not args.sender:
                print("Error: --sender is required for sim mode")
                sys.exit(1)
            if args.mode == 'exec' and not args.account:
                print("Error: --account is required for exec mode")
                sys.exit(1)
            
            success = runner.finalize_withdraw(
                vault_address=args.vault_address,
                account_address=args.account_address,
                wrm_address=args.wrm_address,
                mode=args.mode,
                sender_address=args.sender,
                account_name=args.account,
                gas_estimate_multiplier=args.gas_estimate_multiplier
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'liquidate':
            if args.mode == 'sim' and not args.sender:
                print("Error: --sender is required for sim mode")
                sys.exit(1)
            if args.mode == 'exec' and not args.account:
                print("Error: --account is required for exec mode")
                sys.exit(1)
            
            success = runner.liquidate(
                vault_address=args.vault_address,
                liquidate_account=args.liquidate_account,
                shares_to_liquidate=args.shares_to_liquidate,
                mode=args.mode,
                sender_address=args.sender,
                account_name=args.account,
                gas_estimate_multiplier=args.gas_estimate_multiplier
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'list-vaults':
            vaults = runner.vault_registry.list_supported_vaults()
            if vaults:
                print("Supported vault addresses:")
                for vault in vaults:
                    print(f"  {vault}")
            else:
                print("No vault implementations found")
            sys.exit(0)
    
    except KeyboardInterrupt:
        print("\nOperation cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()