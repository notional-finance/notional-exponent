import os
from typing import Optional
from web3 import Web3



class Web3Helper:
    """Helper class for Web3 operations."""
    
    def __init__(self, rpc_url: Optional[str] = None):
        self.rpc_url = rpc_url or os.getenv('MAINNET_RPC_URL') or os.getenv('RPC_URL')
        if not self.rpc_url:
            raise ValueError("RPC_URL must be provided via parameter or environment variable")
        
        self.w3 = Web3(Web3.HTTPProvider(self.rpc_url))
        
        if not self.w3.is_connected():
            raise ConnectionError(f"Failed to connect to Web3 provider at {self.rpc_url}")
    
    def get_asset_decimals(self, vault_address: str) -> int:
        """Get the decimals of the vault's underlying asset."""
        # ERC20 decimals() function signature
        decimals_signature = self.w3.keccak(text="decimals()")[:4]
        
        # Call asset() on the vault to get the asset address
        asset_signature = self.w3.keccak(text="asset()")[:4]

        checksum_address = Web3.to_checksum_address(vault_address)
        
        try:
            # Get asset address from vault
            asset_result = self.w3.eth.call({
                'to': checksum_address,
                'data': asset_signature.hex()
            })
            asset_address = '0x' + asset_result.hex()[-40:]  # Extract last 20 bytes as address

            checksum_asset_address = Web3.to_checksum_address(asset_address)
            # Get decimals from asset
            decimals_result = self.w3.eth.call({
                'to': checksum_asset_address,
                'data': decimals_signature.hex()
            })
            return int(decimals_result.hex(), 16)
            
        except Exception as e:
            raise RuntimeError(f"Failed to fetch decimals for vault {checksum_address}: {e}") from e
    
    def get_contract_call(self, address: str, function_signature: str) -> bytes:
        """Make a contract call and return raw bytes."""
        signature_hash = self.w3.keccak(text=function_signature)[:4]
        checksum_address = Web3.to_checksum_address(address)
        
        result = self.w3.eth.call({
            'to': checksum_address,
            'data': signature_hash.hex()
        })
        
        return result