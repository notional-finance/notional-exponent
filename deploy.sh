#!/bin/bash

source .env

if [ -z "$1" ]; then
    echo "Usage: $0 <action> <contract-name|vault-address> [--broadcast]"
    echo "  actions: WithdrawRequestManager, LendingRouter, Vault, CreateInitialPosition"
    echo "  --broadcast: broadcast the transaction"
    exit 1
fi

# Check if --broadcast flag is passed
if [[ "$*" == *"--broadcast"* ]]; then
    BROADCAST=true
fi

CONTRACT_NAME=$2
DEPLOYER=MAINNET_V2_DEPLOYER
SENDER="0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3"
if [ "$1" = "WithdrawRequestManager" ]; then
    SCRIPT_NAME="DeployWithdrawManager"
elif [ "$1" = "LendingRouter" ]; then
    SCRIPT_NAME="DeployLendingRouter"
elif [ "$1" = "Vault" ]; then
    SCRIPT_NAME="DeployVault"
elif [ "$1" = "CreateInitialPosition" ]; then
    SCRIPT_NAME="CreateInitialPosition"
    # The vault address is passed as an argument to the script
    CONTRACT_NAME="CreateInitialPosition"
    export VAULT_ADDRESS=$2
    DEPLOYER=HOLDER
    SENDER=0x407e6F2E410e773ED0D1c4f3c7FCFAE0fF67F2ce
else
    echo "Invalid contract name: $1"
    exit 1
fi

SCRIPT="script/$SCRIPT_NAME.sol:$CONTRACT_NAME"

if [ "$BROADCAST" = true ]; then
    forge script $SCRIPT --rpc-url $RPC_URL --chain-id 1 -vv \
        --account $DEPLOYER --broadcast --slow --sender $SENDER \
        --verify --verifier etherscan
else
    forge script $SCRIPT --rpc-url $RPC_URL --chain-id 1 \
        --account $DEPLOYER -vv --sender $SENDER
fi

