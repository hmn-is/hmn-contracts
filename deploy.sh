#!/bin/bash

set -e

source .env

# Run forge script and capture output
OUTPUT=$(forge script script/Deploy.s.sol --rpc-url http://0.0.0.0:8545 --private-key $PRIVATE_KEY --broadcast)
echo "$OUTPUT"

NEXT_PUBLIC_CONTRACT_ADDRESS=$(echo "$OUTPUT" | grep "Manager Proxy:" | awk '{print $3}')

pushd src;
forge inspect HmnManagerImplMainV1 abi > abi/manager.json;
cp abi/manager.json ../../hmn-is/src/abi/manager.json;
popd;

# Update contract address in hmn-is/.env
sed -i.bak "1s|.*|NEXT_PUBLIC_CONTRACT_ADDRESS=$NEXT_PUBLIC_CONTRACT_ADDRESS|" ../hmn-is/.env
rm ../hmn-is/.env.bak