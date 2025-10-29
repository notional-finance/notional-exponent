from decimal import Decimal
from typing import Dict, Any, Tuple
from vault_data.base_vault import BaseVault
from utils.encoding import EncodingHelper
from web3 import Web3


class Vault_0x2716561755154eef59bc48eb13712510b27f167f(BaseVault):
    """Vault implementation for 0x2716561755154eef59bc48eb13712510b27f167f"""
    
    # Constants from the original Solidity file
    CURVE_V2_POOL = "0x2716561755154eef59bc48eb13712510b27f167f"
    LTV = 0.915
    PRIMARY_INDEX = 1

    def get_deposit_data(self, min_purchase_amount: int) -> bytes:
        """Get encoded deposit data for this vault."""
        # This vault doesn't use min_purchase_amount for deposit data
        return EncodingHelper.encode_empty_bytes()
    
    def get_redeem_data(self, min_purchase_amount: int) -> bytes:
        """Get encoded redeem data for this vault."""
        # Single sided exit
        redeem_params = EncodingHelper.encode_single_sided_exit(
            primary_index=self.PRIMARY_INDEX,
            min_purchase_amount=min_purchase_amount
        )
        
        return redeem_params
    
    def get_withdraw_data(self) -> bytes:
        """Get encoded withdraw data for this vault."""
        return EncodingHelper.encode_empty_bytes()
    
    def get_decimals(self) -> Tuple[int, int, int]:
        """Get asset, yield token, and vault share decimals."""
        checksum_address = Web3.to_checksum_address(self.vault_address)
        
        # Get asset decimals
        asset_signature = self.web3_helper.w3.keccak(text="asset()")[:4]
        asset_result = self.web3_helper.w3.eth.call({
            'to': checksum_address,
            'data': asset_signature.hex()
        })
        asset_address = '0x' + asset_result.hex()[-40:]
        
        decimals_signature = self.web3_helper.w3.keccak(text="decimals()")[:4]
        asset_decimals_result = self.web3_helper.w3.eth.call({
            'to': Web3.to_checksum_address(asset_address),
            'data': decimals_signature.hex()
        })
        asset_decimals = int(asset_decimals_result.hex(), 16)
        
        yield_token_decimals = 18
        
        # Get vault share decimals
        vault_decimals_result = self.web3_helper.w3.eth.call({
            'to': checksum_address,
            'data': decimals_signature.hex()
        })
        vault_share_decimals = int(vault_decimals_result.hex(), 16)
        
        return asset_decimals, yield_token_decimals, vault_share_decimals
