from decimal import Decimal, InvalidOperation
from typing import Any, Dict
import re


class ValidationError(Exception):
    """Custom exception for validation errors."""
    pass


class InputValidator:
    """Utility class for validating user inputs."""
    
    @staticmethod
    def validate_address(address: str) -> str:
        """Validate Ethereum address format."""
        if not isinstance(address, str):
            raise ValidationError("Address must be a string")
        
        if not re.match(r'^0x[a-fA-F0-9]{40}$', address):
            raise ValidationError(f"Invalid Ethereum address format: {address}")
        
        return address.lower()
    
    @staticmethod
    def validate_decimal_amount(amount: str) -> Decimal:
        """Validate and convert string amount to Decimal."""
        try:
            decimal_amount = Decimal(str(amount))
            if decimal_amount < 0:
                raise ValidationError("Amount cannot be negative")
            return decimal_amount
        except (InvalidOperation, TypeError):
            raise ValidationError(f"Invalid amount format: {amount}")
    
    @staticmethod
    def validate_mode(mode: str) -> str:
        """Validate execution mode."""
        valid_modes = ['sim', 'exec']
        if mode not in valid_modes:
            raise ValidationError(f"Mode must be one of {valid_modes}, got: {mode}")
        return mode
    
    @staticmethod
    def validate_account_name(account_name: str) -> str:
        """Validate account name for forge."""
        if not isinstance(account_name, str):
            raise ValidationError("Account name must be a string")
        
        if not account_name.strip():
            raise ValidationError("Account name cannot be empty")
        
        return account_name.strip()