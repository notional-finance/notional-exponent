#!/bin/bash

source .env

if [ -z "$1" ]; then
    echo "Usage: $0 (WithdrawRequestManager|LendingRouter|Vault) ContractName"
    echo "  --broadcast: broadcast the transaction"
    exit 1
fi

# Check if --broadcast flag is passed
if [[ "$*" == *"--broadcast"* ]]; then
    BROADCAST=true
fi

if [ "$1" = "WithdrawRequestManager" ]; then
    SCRIPT_NAME="DeployWithdrawManager"
elif [ "$1" = "LendingRouter" ]; then
    SCRIPT_NAME="DeployLendingRouter"
elif [ "$1" = "Vault" ]; then
    SCRIPT_NAME="DeployVault"
else
    echo "Invalid contract name: $1"
    exit 1
fi

CONTRACT_NAME=$2
DEPLOYER=MAINNET_V2_DEPLOYER
SCRIPT="script/$SCRIPT_NAME.sol:$CONTRACT_NAME"

if [ "$BROADCAST" = true ]; then
    forge script $SCRIPT --rpc-url $RPC_URL --chain-id 1 -vv \
        --account $DEPLOYER --broadcast --slow \
        --verify --verifier etherscan
else
    forge script $SCRIPT --rpc-url $RPC_URL --chain-id 1 -vv --account $DEPLOYER
fi

