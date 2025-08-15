source .env
export ETHERSCAN_TOKEN=$API_KEY_ETHERSCAN
export RPC_URL=$MAINNET_RPC_URL

# forge script \
#     CreateInitialPosition \
#     --account DEPLOYER \
#     --sender 0x9299B176bFd1CaBB967ac2A027814FAad8782BA7 \
#     --sig "getInstantRedeemData(address,uint256)" \
#     0x9299B176bFd1CaBB967ac2A027814FAad8782BA7 \
#     1900000

# forge script \
#     ExitPositionAndWithdraw \
#     --sender 0x407e6f2e410e773ed0d1c4f3c7fcfae0ff67f2ce

# forge script \
#     script/vault_data/Data_0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae.sol \
#     --sig "getDepositData()"

forge script \
    script/vault_data/Data_0x7f723feE1E65A7d26bE51A05AF0B5eFEE4a7d5ae.sol \
    --fork-url https://eth-mainnet.g.alchemy.com/v2/pq08EwFvymYFPbDReObtP-SFw3bCes8Z \
    --sender 0x407e6f2e410e773ed0d1c4f3c7fcfae0ff67f2ce \
    --sig "getInstantRedeemData(uint256)" \
    0