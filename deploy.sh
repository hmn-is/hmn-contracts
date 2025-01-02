#!/bin/bash

set -e

source .env

# Check required environment variables
required_vars=(
  "PRIVATE_KEY"
  "ETH_RPC_URL" 
  "ETHERSCAN_API_KEY"
  "ADMIN_ADDRESS"
  "WORLD_ID_ROUTER"
  "NEXT_PUBLIC_WORLD_APP_ID"
  "NEXT_PUBLIC_WORLD_ACTION_HMN"
)

for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Error: Required environment variable $var is not set"
    exit 1
  fi
done

if [ "$1" = "production" ]; then
  OUTPUT=$(forge script script/Deploy.s.sol --rpc-url $ETH_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY)
else
  OUTPUT=$(forge script script/Deploy.s.sol --rpc-url http://0.0.0.0:8545 --private-key $PRIVATE_KEY --broadcast)
fi
echo "$OUTPUT"
NEXT_PUBLIC_MANAGER_CONTRACT_ADDRESS=$(echo "$OUTPUT" | grep "Manager Proxy:" | awk '{print $3}')
NEXT_PUBLIC_HMN_CONTRACT_ADDRESS=$(echo "$OUTPUT" | grep "HMN Token:" | awk '{print $3}')

pushd src;
forge inspect HmnManagerImplMainV1 abi > abi/manager.json;
forge inspect HmnMain abi > abi/hmn.json;
cp abi/manager.json ../../hmn-is/src/abi/manager.json;
cp abi/hmn.json ../../hmn-is/src/abi/hmn.json;
popd;

sed -i.bak "1s|.*|NEXT_PUBLIC_MANAGER_CONTRACT_ADDRESS=$NEXT_PUBLIC_MANAGER_CONTRACT_ADDRESS|" ../hmn-is/.env
rm ../hmn-is/.env.bak

sed -i.bak "2s|.*|NEXT_PUBLIC_HMN_CONTRACT_ADDRESS=$NEXT_PUBLIC_HMN_CONTRACT_ADDRESS|" ../hmn-is/.env
rm ../hmn-is/.env.bak
