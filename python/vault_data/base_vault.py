from abc import ABC, abstractmethod
from typing import Tuple
from web3 import Web3


class BaseVault(ABC):
    """Abstract base class for vault data processing."""
    
    def __init__(self, vault_address: str, web3_helper):
        self.vault_address = vault_address.lower()
        self.web3_helper = web3_helper
    
    @abstractmethod
    def get_deposit_data(self, min_purchase_amount: int) -> bytes:
        """Get encoded deposit data for this vault."""
        pass
    
    @abstractmethod
    def get_redeem_data(self, min_purchase_amount: int) -> bytes:
        """Get encoded redeem data for this vault."""
        pass
    
    @abstractmethod
    def get_withdraw_data(self) -> bytes:
        """Get encoded withdraw data for this vault."""
        pass
    
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
        
        # Get yield token decimals
        yield_token_signature = self.web3_helper.w3.keccak(text="yieldToken()")[:4]
        yield_token_result = self.web3_helper.w3.eth.call({
            'to': checksum_address,
            'data': yield_token_signature.hex()
        })
        yield_token_address = '0x' + yield_token_result.hex()[-40:]
        
        yield_token_decimals_result = self.web3_helper.w3.eth.call({
            'to': Web3.to_checksum_address(yield_token_address),
            'data': decimals_signature.hex()
        })
        yield_token_decimals = int(yield_token_decimals_result.hex(), 16)
        
        # Get vault share decimals
        vault_decimals_result = self.web3_helper.w3.eth.call({
            'to': checksum_address,
            'data': decimals_signature.hex()
        })
        vault_share_decimals = int(vault_decimals_result.hex(), 16)
        
        return asset_decimals, yield_token_decimals, vault_share_decimals
    
    
