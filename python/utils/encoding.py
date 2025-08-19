from eth_abi import encode


class EncodingHelper:
    """Helper class for ABI encoding operations."""
    
    @staticmethod
    def encode_curve_v2_single_data(pool: str, from_index: int, to_index: int) -> bytes:
        """Encode CurveV2SingleData struct."""
        return encode(
            ['address', 'int128', 'int128'],
            [pool, from_index, to_index]
        )
    
    @staticmethod
    def encode_redeem_params(dex_id: int, min_purchase_amount: int, exchange_data: bytes) -> bytes:
        """Encode RedeemParams struct to match Solidity's abi.encode(RedeemParams(...))."""
        return encode(
            ['(uint8,uint256,bytes)'],  # Tuple type for the struct
            [(dex_id, min_purchase_amount, exchange_data)]
        )
    
    @staticmethod
    def encode_staking_trade_params(trade_type: int, min_purchase_amount: int, 
                                  exchange_data: bytes, dex_id: int, stake_data: bytes) -> bytes:
        """Encode StakingTradeParams struct to match Solidity's abi.encode(StakingTradeParams(...))."""
        return encode(
            ['(uint8,uint256,bytes,uint16,bytes)'],  # Tuple type for the struct
            [(trade_type, min_purchase_amount, exchange_data, dex_id, stake_data)]
        )
    
    @staticmethod
    def encode_empty_bytes() -> bytes:
        """Return empty bytes for deposit data."""
        return b""
    
    @staticmethod
    def hex_to_bytes(hex_string: str) -> bytes:
        """Convert hex string to bytes, handling 0x prefix."""
        if hex_string.startswith('0x'):
            hex_string = hex_string[2:]
        return bytes.fromhex(hex_string)
    
    @staticmethod
    def bytes_to_hex(data: bytes) -> str:
        """Convert bytes to hex string with 0x prefix."""
        return '0x' + data.hex()