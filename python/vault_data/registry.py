import os
import importlib.util
from typing import Dict, Type, Optional
from vault_data.base_vault import BaseVault


class VaultRegistry:
    """Registry for managing vault implementations."""
    
    def __init__(self):
        self._vaults: Dict[str, Type[BaseVault]] = {}
        self._discover_vaults()
    
    def _discover_vaults(self):
        """Automatically discover and register vault implementations."""
        vault_data_dir = os.path.dirname(__file__)
        
        for filename in os.listdir(vault_data_dir):
            if filename.startswith('vault_0x') and filename.endswith('.py'):
                vault_address = self._extract_address_from_filename(filename)
                if vault_address:
                    try:
                        module_name = filename[:-3]  # Remove .py extension
                        module_path = os.path.join(vault_data_dir, filename)
                        
                        # Use importlib to import with proper package context
                        spec = importlib.util.spec_from_file_location(f"vault_data.{module_name}", module_path)
                        if spec and spec.loader:
                            module = importlib.util.module_from_spec(spec)
                            # Add the vault_data package to sys.modules so relative imports work
                            import sys
                            sys.modules[f"vault_data.{module_name}"] = module
                            spec.loader.exec_module(module)
                            
                            # Look for a class that inherits from BaseVault
                            for attr_name in dir(module):
                                attr = getattr(module, attr_name)
                                if (isinstance(attr, type) and 
                                    issubclass(attr, BaseVault) and 
                                    attr != BaseVault):
                                    self._vaults[vault_address] = attr
                                    break
                    
                    except Exception as e:
                        print(f"Warning: Failed to load vault module {filename}: {e}")
    
    def _extract_address_from_filename(self, filename: str) -> Optional[str]:
        """Extract vault address from filename like vault_0x123...abc.py"""
        try:
            if filename.startswith('vault_0x') and filename.endswith('.py'):
                address = filename[6:-3]  # Remove 'vault_' prefix and '.py' suffix
                if len(address) == 42 and address.startswith('0x'):
                    return address.lower()
        except Exception:
            pass
        return None
    
    def get_vault_class(self, vault_address: str) -> Optional[Type[BaseVault]]:
        """Get the vault class for a given address."""
        return self._vaults.get(vault_address.lower())
    
    def create_vault(self, vault_address: str, web3_helper) -> Optional[BaseVault]:
        """Create a vault instance for the given address."""
        vault_class = self.get_vault_class(vault_address)
        if vault_class:
            return vault_class(vault_address, web3_helper)
        return None
    
    def list_supported_vaults(self) -> list[str]:
        """List all supported vault addresses."""
        return list(self._vaults.keys())
    
    def register_vault(self, vault_address: str, vault_class: Type[BaseVault]):
        """Manually register a vault class."""
        self._vaults[vault_address.lower()] = vault_class