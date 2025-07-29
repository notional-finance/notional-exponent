#!/bin/bash

source .env

if [ -z "$1" ]; then
    echo "Usage: $0 <script>"
    echo "  --broadcast: broadcast the transaction"
    exit 1
fi
# Check if --broadcast flag is passed
if [[ "$*" == *"--broadcast"* ]]; then
    BROADCAST=true
fi

DEPLOYER=MAINNET_V2_DEPLOYER

if [ "$BROADCAST" = true ]; then
    forge script $1 --rpc-url $RPC_URL --chain-id 1 -vv \
        --account $DEPLOYER --broadcast --slow \
        --verify --verifier etherscan
else
    forge script $1 --rpc-url $RPC_URL --chain-id 1 -vv --account $DEPLOYER
fi

