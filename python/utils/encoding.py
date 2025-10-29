from eth_abi import encode
from eth_abi.packed import encode_packed


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

    @staticmethod
    def encode_single_sided_exit(primary_index: int, min_purchase_amount: int) -> bytes:
        """Encode RedeemParams struct for single-sided exit.

        Args:
            primary_index: Index (0 or 1) where min_purchase_amount should be placed
            min_purchase_amount: Minimum amount expected for slippage control

        Returns:
            Encoded RedeemParams struct with minAmounts and empty redemptionTrades
        """
        # Create minAmounts array with min_purchase_amount at primary_index, 0 at other
        min_amounts = [0, 0]
        min_amounts[primary_index] = min_purchase_amount

        # Encode RedeemParams: (uint256[] minAmounts, TradeParams[] redemptionTrades)
        # TradeParams structure: (uint256 tradeAmount, uint16 dexId, uint8 tradeType,
        #                         uint256 minPurchaseAmount, bytes exchangeData)
        # For single-sided exit, redemptionTrades is empty
        return encode(
            ['(uint256[],(uint256,uint16,uint8,uint256,bytes)[])'],
            [(min_amounts, [])]
        )