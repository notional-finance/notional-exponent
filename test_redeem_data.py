#!/usr/bin/env python3
"""
Script to test if Python vault redeem data matches Solidity test implementation
"""

import sys
import os

# Add python directory to path
python_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'python')
sys.path.insert(0, python_dir)

from utils.encoding import EncodingHelper
from eth_abi import encode

def encode_redeem_params_tuple(dex_id: int, min_purchase_amount: int, exchange_data: bytes) -> bytes:
    """Alternative encoding method that matches Solidity's abi.encode(RedeemParams(...))"""
    return encode(
        ['(uint8,uint256,bytes)'],  # Tuple type for the struct
        [(dex_id, min_purchase_amount, exchange_data)]
    )

def test_redeem_data_encoding():
    """Test that our encoding matches the expected Solidity output."""
    
    # Constants from the vault implementation
    CURVE_V2_POOL = "0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5"
    FROM_INDEX = 1
    TO_INDEX = 0
    DEX_ID_CURVE_V2 = 7
    
    # Test with min_purchase_amount = 0 to match Solidity test
    min_purchase_amount = 0
    
    print("Testing redeem data encoding...")
    print(f"Pool: {CURVE_V2_POOL}")
    print(f"From Index: {FROM_INDEX}")
    print(f"To Index: {TO_INDEX}")
    print(f"Dex ID: {DEX_ID_CURVE_V2}")
    print(f"Min Purchase Amount: {min_purchase_amount}")
    print()
    
    # Step 1: Encode CurveV2SingleData
    curve_data = EncodingHelper.encode_curve_v2_single_data(
        pool=CURVE_V2_POOL,
        from_index=FROM_INDEX,
        to_index=TO_INDEX
    )
    print(f"Encoded CurveV2SingleData: {curve_data.hex()}")
    
    # Step 2: Encode RedeemParams
    redeem_params = EncodingHelper.encode_redeem_params(
        dex_id=DEX_ID_CURVE_V2,
        min_purchase_amount=min_purchase_amount,
        exchange_data=curve_data
    )
    print(f"Encoded RedeemParams: {redeem_params.hex()}")
    print()
    
    # Also test with a non-zero min_purchase_amount 
    min_purchase_amount_test = 1000000000000000000  # 1 ether in wei
    redeem_params_test = EncodingHelper.encode_redeem_params(
        dex_id=DEX_ID_CURVE_V2,
        min_purchase_amount=min_purchase_amount_test,
        exchange_data=curve_data
    )
    print(f"With min_purchase_amount=1e18: {redeem_params_test.hex()}")
    print()
    
    # Test the new tuple-based encoding method
    print("=== Testing new tuple-based encoding method ===")
    redeem_params_tuple = encode_redeem_params_tuple(
        dex_id=DEX_ID_CURVE_V2,
        min_purchase_amount=min_purchase_amount,
        exchange_data=curve_data
    )
    print(f"Tuple-based RedeemParams (min=0): {redeem_params_tuple.hex()}")
    
    # Test with 1 ether min purchase amount
    redeem_params_tuple_test = encode_redeem_params_tuple(
        dex_id=DEX_ID_CURVE_V2,
        min_purchase_amount=min_purchase_amount_test,
        exchange_data=curve_data
    )
    print(f"Tuple-based RedeemParams (min=1e18): {redeem_params_tuple_test.hex()}")
    
    return redeem_params

if __name__ == "__main__":
    test_redeem_data_encoding()