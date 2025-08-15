from abc import ABC, abstractmethod
from typing import Dict, Any, Optional
from decimal import Decimal


class BaseVault(ABC):
    """Abstract base class for vault data processing."""
    
    def __init__(self, vault_address: str, web3_helper):
        self.vault_address = vault_address.lower()
        self.web3_helper = web3_helper
        self._asset_decimals: Optional[int] = None
    
    @abstractmethod
    def get_deposit_data(self) -> bytes:
        """Get encoded deposit data for this vault."""
        pass
    
    @abstractmethod
    def get_redeem_data(self, min_purchase_amount: int) -> bytes:
        """Get encoded redeem data for this vault."""
        pass
    
    def get_asset_decimals(self) -> int:
        """Get the number of decimals for the vault's underlying asset."""
        if self._asset_decimals is None:
            self._asset_decimals = self.web3_helper.get_asset_decimals(self.vault_address)
        return self._asset_decimals
    
    def scale_user_input(self, amount: Decimal) -> int:
        """Convert user-friendly decimal amount to wei-based integer."""
        decimals = self.get_asset_decimals()
        return int(amount * (10 ** decimals))
    
    def validate_inputs(self, **kwargs) -> Dict[str, Any]:
        """Validate and process user inputs."""
        return kwargs