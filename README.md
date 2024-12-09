# HMN Contracts

This repository contains the HMN token and on-chain registry system for unique human wallets. The registry builds on [Worldcoin Foundation](https://foundation.world.org/)'s [World ID system](https://world.org/world-id) for anonymous verification of unique humanness.

HMN is the first stage in a set of experiment towards creating a new financial system where a) each participant has exactly one (set of verified and linked) account(s), b) each participating account is verified and trusted, and eventually c) the system covers all real world assets ands resources, including ones that are currently considered externalities.

While creating a Mutually Exclusive and Commonly Exhaustive capital system is impossibly hard, we have a plan on how to get there and believe that even a one percent change is well worth the effort. A well governed and trustless MECE financial system would have the potential of solving most of humanity's most pressing and most difficult problems such as global warming, loss of biodiversity, pollution, tax evasion, unemployment (via universal income), and disproportionate accumulation of wealth.

For more information on the project, see [hmn.is](https://hmn.is).

## Contract Overview

### HMN Token

Non-upgradeable HMN token contracts consist of `HmnBase` base contract with transfer control, `HmnMain` master token for ETH Mainnet and `HmnSlave` token for L2s. The token contracts serve as a trustless currency with minimal attack surface, while also providing novel features like account recovery and unverified-transfer tax for discouraging fake accounts and non-human users.

### HMN Manager and Bridges

Delay-upgradeable, HMN Manager and bridge contracts for maintaining an on-chain registry of verified unique human wallets and trusted (non-bot, non-fake account) contracts, that serve as a central repository of verified human users across all blockchains.

## Develpment Instuctions

### Building

```shell
forge build
```

### Local deployment

```shell
anvil -f https://worldchain-sepolia.g.alchemy.com/v2/your_code --chain-id 4801 --block-time 10

forge script script/Deploy.s.sol --rpc-url http://0.0.0.0:8545 --private-key <your_private_key>
```

### Generate ABI files

```shell
pushd src; forge inspect HmnMangerImplMainV1 abi > abi/manager.json; popd
```
