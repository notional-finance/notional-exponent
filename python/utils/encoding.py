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
        """Encode RedeemParams struct."""
        return encode(
            ['uint8', 'uint256', 'bytes'],
            [dex_id, min_purchase_amount, exchange_data]
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