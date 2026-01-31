from decimal import Decimal
from typing import Dict, Any
from vault_data.base_vault import BaseVault
from utils.encoding import EncodingHelper


class Vault_0xaf14d06a65c91541a5b2db627ecd1c92d7d9c48b(BaseVault):
    """Vault implementation for 0xaf14d06a65c91541a5b2db627ecd1c92d7d9c48b"""
    
    # Constants from the original Solidity file
    USDC_USDe_POOL = "0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72"
    DEX_ID_CURVE_V2 = 7  # From DexId enum: CURVE_V2 = 7
    LTV = 0.915
    
    def get_deposit_data(self, min_purchase_amount: int) -> bytes:

        exchange_data = EncodingHelper.encode_curve_v2_single_data(
            pool=self.USDC_USDe_POOL,
            from_index=1,
            to_index=0
        )

        stake_data = EncodingHelper.encode_empty_bytes()

        deposit_params = EncodingHelper.encode_staking_trade_params(
            trade_type=1,
            min_purchase_amount=min_purchase_amount,
            exchange_data=exchange_data,
            dex_id=self.DEX_ID_CURVE_V2,
            stake_data=stake_data
        )

        return deposit_params
    
    def get_redeem_data(self, min_purchase_amount: int) -> bytes:
        pass
    
    def get_withdraw_data(self) -> bytes:
        """Get encoded withdraw data for this vault."""
        return EncodingHelper.encode_empty_bytes()
    
