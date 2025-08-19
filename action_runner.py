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
    
    def create_initial_position(self, vault_address: str, initial_deposit: str, 
                              initial_supply: str, initial_borrow: str,
                              min_purchase_amount: str, mode: str, 
                              sender_address: Optional[str] = None,
                              account_name: Optional[str] = None,
                              gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Execute CreateInitialPosition action."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            mode = InputValidator.validate_mode(mode)
            
            initial_deposit_decimal = InputValidator.validate_decimal_amount(initial_deposit)
            initial_supply_decimal = InputValidator.validate_decimal_amount(initial_supply)
            initial_borrow_decimal = InputValidator.validate_decimal_amount(initial_borrow)
            min_purchase_decimal = InputValidator.validate_decimal_amount(min_purchase_amount)
            
            # Get vault implementation
            vault = self.vault_registry.create_vault(vault_address, self.web3_helper)
            if not vault:
                print(f"Error: No vault implementation found for address {vault_address}")
                print(f"Supported vaults: {self.vault_registry.list_supported_vaults()}")
                return False
            
            print(f"Using vault implementation for {vault_address}")
            
            # Scale user inputs to proper decimals
            scaled_deposit = vault.scale_user_input(initial_deposit_decimal)
            scaled_supply = vault.scale_user_input(initial_supply_decimal)
            scaled_borrow = vault.scale_user_input(initial_borrow_decimal)
            scaled_min_purchase = vault.scale_user_input(min_purchase_decimal)
            
            print(f"Scaled values - Deposit: {scaled_deposit}, Supply: {scaled_supply}, Borrow: {scaled_borrow}, Min Purchase: {scaled_min_purchase}")
            
            # Get deposit data
            deposit_data = vault.get_deposit_data(scaled_min_purchase)
            deposit_data_hex = EncodingHelper.bytes_to_hex(deposit_data)
            
            print(f"Deposit data: {deposit_data_hex}")
            
            # Build forge command
            forge_cmd = self._build_forge_command(
                action_script="script/actions/CreateInitialPosition.sol",
                vault_address=vault_address,
                initial_supply=scaled_supply,
                initial_borrow=scaled_borrow,
                initial_deposit=scaled_deposit,
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
    
    def exit_position_and_withdraw(self, vault_address: str, min_purchase_amount: str,
                                 mode: str, sender_address: Optional[str] = None,
                                 account_name: Optional[str] = None,
                                 gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Execute ExitPositionAndWithdraw action."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            mode = InputValidator.validate_mode(mode)
            min_purchase_decimal = InputValidator.validate_decimal_amount(min_purchase_amount)
            
            # Get vault implementation
            vault = self.vault_registry.create_vault(vault_address, self.web3_helper)
            if not vault:
                print(f"Error: No vault implementation found for address {vault_address}")
                return False
            
            # Scale user input
            scaled_min_purchase = vault.scale_user_input(min_purchase_decimal)
            
            # Get redeem data
            redeem_data = vault.get_redeem_data(scaled_min_purchase)
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
        """Execute ExitPosition action."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            mode = InputValidator.validate_mode(mode)
            
            shares_to_redeem_decimal = InputValidator.validate_decimal_amount(shares_to_redeem)
            asset_to_repay_decimal = InputValidator.validate_decimal_amount(asset_to_repay)
            min_purchase_decimal = InputValidator.validate_decimal_amount(min_purchase_amount)
            
            # Get vault implementation
            vault = self.vault_registry.create_vault(vault_address, self.web3_helper)
            if not vault:
                print(f"Error: No vault implementation found for address {vault_address}")
                return False
            
            print(f"Exiting position for vault {vault_address}")
            
            # Scale user inputs
            # shares_to_redeem is in 1e24 precision
            scaled_shares = int(shares_to_redeem_decimal * (10 ** 24))
            # asset_to_repay is in native precision
            scaled_asset_repay = vault.scale_user_input(asset_to_repay_decimal)
            scaled_min_purchase = vault.scale_user_input(min_purchase_decimal)
            
            print(f"Scaled values - Shares: {scaled_shares}, Asset to Repay: {scaled_asset_repay}, Min Purchase: {scaled_min_purchase}")
            
            # Get redeem data
            redeem_data = vault.get_redeem_data(scaled_min_purchase)
            redeem_data_hex = EncodingHelper.bytes_to_hex(redeem_data)
            
            print(f"Redeem data: {redeem_data_hex}")
            
            # Build and execute forge command
            forge_cmd = self._build_exit_position_forge_command(
                vault_address=vault_address,
                shares_to_redeem=scaled_shares,
                asset_to_repay=scaled_asset_repay,
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
    
    def withdraw_from_morpho(self, vault_address: str, mode: str,
                           sender_address: Optional[str] = None,
                           account_name: Optional[str] = None,
                           gas_estimate_multiplier: Optional[int] = None) -> bool:
        """Execute WithdrawFromMorpho action."""
        try:
            # Validate inputs
            vault_address = InputValidator.validate_address(vault_address)
            mode = InputValidator.validate_mode(mode)
            
            print(f"Withdrawing from Morpho for vault {vault_address}")
            
            # Build and execute forge command
            forge_cmd = self._build_morpho_withdraw_forge_command(
                vault_address=vault_address,
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
    
    def _build_forge_command(self, action_script: str, vault_address: str,
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
    
    def _build_morpho_withdraw_forge_command(self, vault_address: str, mode: str,
                                           sender_address: Optional[str] = None,
                                           account_name: Optional[str] = None,
                                           gas_estimate_multiplier: Optional[int] = None) -> list[str]:
        """Build forge command arguments for Morpho withdraw."""
        cmd = [
            "forge", "script", "script/actions/WithdrawFromMorpho.sol",
            "--sig", "run(address)"
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
            vault_address
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


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Python-based action runner for vault operations")
    
    subparsers = parser.add_subparsers(dest='action', help='Action to perform')
    
    # Create initial position command
    create_parser = subparsers.add_parser('create-position', help='Create initial position')
    create_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    create_parser.add_argument('vault_address', help='Vault contract address')
    create_parser.add_argument('initial_deposit', help='Initial deposit amount')
    create_parser.add_argument('initial_supply', help='Initial supply amount')
    create_parser.add_argument('initial_borrow', help='Initial borrow amount')
    create_parser.add_argument('min_purchase_amount', help='Minimum purchase amount for slippage protection')
    create_parser.add_argument('--sender', help='Sender address (for sim mode)')
    create_parser.add_argument('--account', help='Account name (for exec mode)')
    create_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')
    
    # Exit position and withdraw command
    exit_and_withdraw_parser = subparsers.add_parser('exit-position-and-withdraw', help='Exit position and withdraw')
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
    morpho_parser.add_argument('--sender', help='Sender address (for sim mode)')
    morpho_parser.add_argument('--account', help='Account name (for exec mode)')
    morpho_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')
    
    # Initiate withdraw command
    initiate_parser = subparsers.add_parser('initiate-withdraw', help='Initiate withdraw request for vault assets')
    initiate_parser.add_argument('mode', choices=['sim', 'exec'], help='Execution mode')
    initiate_parser.add_argument('vault_address', help='Vault contract address')
    initiate_parser.add_argument('--sender', help='Sender address (for sim mode)')
    initiate_parser.add_argument('--account', help='Account name (for exec mode)')
    initiate_parser.add_argument('--gas-estimate-multiplier', type=int, help='Gas estimate multiplier (>100, e.g., 150 for 50%% increase)')
    
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
                initial_deposit=args.initial_deposit,
                initial_supply=args.initial_supply,
                initial_borrow=args.initial_borrow,
                min_purchase_amount=args.min_purchase_amount,
                mode=args.mode,
                sender_address=args.sender,
                account_name=args.account,
                gas_estimate_multiplier=args.gas_estimate_multiplier
            )
            sys.exit(0 if success else 1)
            
        elif args.action == 'exit-position-and-withdraw':
            if args.mode == 'sim' and not args.sender:
                print("Error: --sender is required for sim mode")
                sys.exit(1)
            if args.mode == 'exec' and not args.account:
                print("Error: --account is required for exec mode")
                sys.exit(1)
            
            success = runner.exit_position_and_withdraw(
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