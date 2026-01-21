from decimal import Decimal
from typing import Dict, Any
from vault_data.base_vault import BaseVault
from utils.encoding import EncodingHelper


class Vault_0x94f6cb4fae0eb3fa74e9847dff2ff52fd5ec7e6e(BaseVault):
    """Vault implementation for 0x94f6cb4fae0eb3fa74e9847dff2ff52fd5ec7e6e"""
    
    # Constants from the original Solidity file
    LTV = 0.86

    def get_deposit_data(self, min_purchase_amount: int) -> bytes:
        """Get encoded deposit data for this vault."""
        # This vault doesn't use min_purchase_amount for deposit data
        return EncodingHelper.encode_min_amount(min_purchase_amount)
    
    def get_redeem_data(self, min_purchase_amount: int) -> bytes:
        """Get encoded redeem data for this vault."""
        # Encode min amount
        return EncodingHelper.encode_min_amount(min_purchase_amount)
    
    def get_withdraw_data(self) -> bytes:
        """Get encoded withdraw data for this vault."""
        return EncodingHelper.encode_empty_bytes()
    
