#!/bin/bash

source .env
export ETHERSCAN_TOKEN=$API_KEY_ETHERSCAN
export RPC_URL=$MAINNET_RPC_URL

if [ "$#" -lt 5 ] || [ "$#" -gt 6 ]; then
    echo "Usage:"
    echo "  Simulation mode: $0 sim <vault_address> <initial_deposit> <initial_supply> <initial_borrow> <sender_address>"
    echo "  Execution mode:  $0 exec <vault_address> <initial_deposit> <initial_supply> <initial_borrow> <account_name>"
    echo ""
    echo "Examples:"
    echo "  $0 sim 0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae 1000 2000 500 0x1234567890123456789012345678901234567890"
    echo "  $0 exec 0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae 1000 2000 500 myaccount"
    exit 1
fi

MODE=$1
VAULT_ADDRESS=$2
INITIAL_DEPOSIT=$3
INITIAL_SUPPLY=$4
INITIAL_BORROW=$5

if [ "$MODE" = "sim" ]; then
    SENDER_ADDRESS=$6
    if [ -z "$SENDER_ADDRESS" ]; then
        echo "Error: Sender address is required for simulation mode"
        exit 1
    fi
elif [ "$MODE" = "exec" ]; then
    ACCOUNT_NAME=$6
    if [ -z "$ACCOUNT_NAME" ]; then
        echo "Error: Account name is required for execution mode"
        exit 1
    fi
else
    echo "Error: Mode must be either 'sim' or 'exec'"
    exit 1
fi

echo "Getting deposit data for vault: $VAULT_ADDRESS"

# Construct the data filename
DATA_FILE="script/vault_data/Data_${VAULT_ADDRESS}.sol"

if [ ! -f "$DATA_FILE" ]; then
    echo "Error: Data file $DATA_FILE does not exist"
    exit 1
fi

echo "Using data file: $DATA_FILE"

# Get deposit data
echo "Getting deposit data..."
DEPOSIT_DATA=$(forge script "$DATA_FILE" --sig "getDepositData()" --fork-url $RPC_URL)

echo "Deposit data: $DEPOSIT_DATA"

# Call CreateInitialPosition.sol with the scaled values
echo "Creating initial position..."
if [ "$MODE" = "sim" ]; then
    echo "Running in simulation mode with sender: $SENDER_ADDRESS"
    echo "VAULT_ADDRESS: $VAULT_ADDRESS"
    echo "INITIAL_SUPPLY: $INITIAL_SUPPLY"
    echo "INITIAL_BORROW: $INITIAL_BORROW"
    echo "INITIAL_DEPOSIT: $INITIAL_DEPOSIT"
    echo "DEPOSIT_DATA: $DEPOSIT_DATA"
    echo "SENDER_ADDRESS: $SENDER_ADDRESS"
    echo "RPC_URL: $RPC_URL"
    forge script script/actions/CreateInitialPosition.sol \
        --fork-url $RPC_URL \
        --sig "run(address,uint256,uint256,uint256,bytes)" \
        $VAULT_ADDRESS \
        $INITIAL_SUPPLY \
        $INITIAL_BORROW \
        $INITIAL_DEPOSIT \
        $DEPOSIT_DATA \
        --sender $SENDER_ADDRESS
elif [ "$MODE" = "exec" ]; then
    echo "Running in execution mode with account: $ACCOUNT_NAME"
    forge script script/actions/CreateInitialPosition.sol \
        --sig "run(address,uint256,uint256,uint256,bytes)" \
        --rpc-url $RPC_URL \
        "$VAULT_ADDRESS" \
        "$INITIAL_SUPPLY" \
        "$INITIAL_BORROW" \
        "$INITIAL_DEPOSIT" \
        "$DEPOSIT_DATA" \
        --account "$ACCOUNT_NAME" \
        --broadcast
fi

echo "Initial position creation completed!"