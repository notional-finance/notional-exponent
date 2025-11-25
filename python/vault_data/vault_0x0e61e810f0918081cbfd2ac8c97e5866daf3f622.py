from decimal import Decimal
from typing import Dict, Any
from vault_data.base_vault import BaseVault
from utils.encoding import EncodingHelper
from web3 import Web3
import requests
from eth_abi import encode


class Vault_0x0e61e810f0918081cbfd2ac8c97e5866daf3f622(BaseVault):
    """Vault implementation for 0x0e61e810f0918081cbfd2ac8c97e5866daf3f622"""

    VAULT_ADDRESS = '0x0e61e810f0918081cbfd2ac8c97e5866daf3f622'

    PENDLE_API_URL = 'https://api-v2.pendle.finance/core/v2/sdk'

    ORDER_TYPE = '(uint256 salt, uint256 expiry, uint256 nonce, uint8 orderType, address token, address YT, address maker, address receiver, uint256 makingAmount, uint256 lnImpliedRate, uint256 failSafeRate, bytes permit)'
    FILL_ORDER_PARAMS_TYPE = f'({ORDER_TYPE} order, bytes signature, uint256 makingAmount)'
    LIMIT_ORDER_TYPE = f'(address limitRouter, uint256 epsSkipMarket, {FILL_ORDER_PARAMS_TYPE}[] normalFills, {FILL_ORDER_PARAMS_TYPE}[] flashFills, bytes optData)'

    PT_ADDRESS = '0xe6A934089BBEe34F832060CE98848359883749B3'
    TOKEN_OUT_SY_ADDRESS = '0x9D39A5DE30e57443BfF2A8307A4256c8797A3497'
    SLIPPAGE = 0.001

    LTV = 0.915

    def fetch_pendle_limit_order_data(self, yield_token_amount: int) -> bytes:
        """
        Fetch and encode Pendle limit order data from the Pendle API.

        Args:
            yield_token_amount: Amount of yield tokens to convert (uint256)

        Returns:
            Encoded limit order data as bytes
        """
        network_id = 1  # Mainnet
        receiver = self.vault_address
        slippage = self.SLIPPAGE
        token_out_sy = self.TOKEN_OUT_SY_ADDRESS
        pt_address = self.PT_ADDRESS

        # Build API URL
        api_url = (
            f"{self.PENDLE_API_URL}/{network_id}/convert"
            f"?receiver={receiver}"
            f"&slippage={slippage}"
            f"&enableAggregator=false"
            f"&tokensIn={pt_address}"
            f"&tokensOut={token_out_sy}"
            f"&amountsIn={yield_token_amount}"
        )

        print(f"Fetching Pendle limit order data from: {api_url}")

        try:
            response = requests.get(api_url)

            if not response.ok:
                print(f"Pendle API request failed: {response.status_code} {response.reason}")
                return bytes.fromhex('')

            data = response.json()

            print(f"Pendle API response: {data}")
            print('--------------------------------')

            print(f"Contract Call Params: {data['routes'][0]['contractParamInfo']['contractCallParams']}")
            print('--------------------------------')

            # Check if there are normal or flash fills
            contract_params = data['routes'][0]['contractParamInfo']['contractCallParams'][4]
            print(f"Contract params: {contract_params}")
            print('--------------------------------')

            if (len(contract_params.get('normalFills', [])) > 0 or
                len(contract_params.get('flashFills', [])) > 0):

                # Only encode the limit order data if there are normal or flash fills
                # The LIMIT_ORDER_TYPE is already defined in the class
                pendle_data = encode(
                    [self.LIMIT_ORDER_TYPE],
                    [contract_params]
                )
                return pendle_data

            return bytes.fromhex('')

        except Exception as e:
            print(f"Error fetching Pendle limit order data: {e}")
            return bytes.fromhex('')

    def get_deposit_data(self, min_purchase_amount: int) -> bytes:

        # TODO: Implement deposit data
        """Get encoded deposit data for this vault."""
        return EncodingHelper.encode_empty_bytes()
    
    def get_redeem_data(self, min_purchase_amount: int, shares_to_redeem: int = None) -> bytes:
        """
        Get encoded redeem data for this vault.

        Args:
            min_purchase_amount: Minimum purchase amount for slippage protection
            shares_to_redeem: Amount of vault shares to redeem (required for Pendle vault)

        Returns:
            Encoded redeem data as bytes
        """
        if shares_to_redeem is None:
            # If no shares provided, return empty bytes
            return EncodingHelper.encode_empty_bytes()

        # Encode exchange data for Curve pool (USDC/USDT/DAI)
        exchange_data = encode(
            ['address', 'int128', 'int128'],
            ['0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7', 0, 1]
        )

        # Convert shares to yield tokens
        yield_token_amount = self.get_shares_to_yield_tokens(shares_to_redeem)
        print(f"Converting {shares_to_redeem} shares to {yield_token_amount} yield tokens")

        # Fetch Pendle limit order data
        limit_order_data = self.fetch_pendle_limit_order_data(yield_token_amount)

        # Encode redeem parameters
        # dexId = 7 (for Pendle)
        redeem_params = encode(
            ['(uint8,uint256,bytes,bytes)'],
            [(7, min_purchase_amount, exchange_data, limit_order_data)]
        )

        return redeem_params
        
    def get_withdraw_data(self) -> bytes:
        """Get encoded withdraw data for this vault."""
        return EncodingHelper.encode_empty_bytes()

    def get_shares_to_yield_tokens(self, shares: int) -> int:
        """
        Convert vault shares to yield token amount using convertSharesToYieldToken.

        Args:
            shares: Amount of vault shares (uint256)

        Returns:
            Amount of yield tokens (uint256)
        """
        checksum_address = Web3.to_checksum_address(self.vault_address)

        # Create function signature: convertSharesToYieldToken(uint256)
        function_signature = self.web3_helper.w3.keccak(text="convertSharesToYieldToken(uint256)")[:4]

        # Encode the uint256 parameter (shares)
        # uint256 is 32 bytes, pad to 64 hex characters (32 bytes)
        shares_hex = hex(shares)[2:].zfill(64)

        # Combine function signature and parameter
        call_data = function_signature.hex() + shares_hex

        # Call the contract
        result = self.web3_helper.w3.eth.call({
            'to': checksum_address,
            'data': call_data
        })

        # Decode the uint256 result
        yield_token_amount = int(result.hex(), 16)

        return yield_token_amount
    
