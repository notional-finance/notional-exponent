from decimal import Decimal
from typing import Dict, Any
from vault_data.base_vault import BaseVault
from utils.encoding import EncodingHelper


class Vault_0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae(BaseVault):
    """Vault implementation for 0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae"""
    
    # Constants from the original Solidity file
    CURVE_V2_POOL = "0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5"
    DEX_ID_CURVE_V2 = 7  # From DexId enum: CURVE_V2 = 7
    LTV = 0.945

    def get_deposit_data(self, min_purchase_amount: int) -> bytes:
        """Get encoded deposit data for this vault."""
        # This vault doesn't use min_purchase_amount for deposit data
        return EncodingHelper.encode_empty_bytes()
    
    def get_redeem_data(self, min_purchase_amount: int) -> bytes:
        """Get encoded redeem data for this vault."""
        # Encode CurveV2SingleData
        curve_data = EncodingHelper.encode_curve_v2_single_data(
            pool=self.CURVE_V2_POOL,
            from_index=1,
            to_index=0
        )
        
        # Encode RedeemParams
        redeem_params = EncodingHelper.encode_redeem_params(
            dex_id=self.DEX_ID_CURVE_V2,
            min_purchase_amount=min_purchase_amount,
            exchange_data=curve_data
        )
        
        return redeem_params
    
    def get_withdraw_data(self) -> bytes:
        """Get encoded withdraw data for this vault."""
        return EncodingHelper.encode_empty_bytes()
    
    def validate_inputs(self, **kwargs) -> Dict[str, Any]:
        """Validate and process inputs specific to this vault."""
        validated = super().validate_inputs(**kwargs)
        
        # Add any vault-specific validations here
        if 'min_purchase_amount' in validated:
            min_amount = validated['min_purchase_amount']
            if isinstance(min_amount, str):
                validated['min_purchase_amount'] = self.scale_user_input(Decimal(min_amount))
        
        return validated