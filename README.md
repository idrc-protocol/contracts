## Overview

This repository contains the IDRC yield hub system built on Foundry. The on-chain architecture is composed of:

- `Hub`: an upgradeable coordinator that tracks supported assets, enforces admin-controlled pricing, and handles user subscriptions/redemptions for IDRC shares.
- `IDRC`: an upgradeable ERC20 token minted and burned exclusively by the hub to represent user shares.
- `IDRX`: a simple ERC20 token used throughout the test suite as the underlying asset provided by users.

Upgradeable deployments are instantiated behind `ERC1967Proxy` proxies, and the hub relies on a storage library pattern (`HubStorage`) to maintain state. Administrative control is managed with OpenZeppelin `AccessControl` roles: the deployer retains the default admin role, while a delegated operator receives `ADMIN_ROLE` privileges for pricing updates.

## Quick Start

Install dependencies and run the standard Foundry tasks from the project root:

```bash
forge install
forge build
forge test
```

### Running Tests

Unit tests live under `test/Integration.t.sol`. They cover initialization, pricing, share minting, redemption flows, and access-control error handling, and they also assert that proxy deployments match the deterministic addresses predicted with `vm.computeCreateAddress`.
Execute the full suite with:

```bash
forge test
```

To focus on a single test (for example, the insufficient balance redemption check), use:

```bash
forge test --match-test testRequestRedemptionRevertsForInsufficientBalance
```

### Deploy Scripts

The main deployment entrypoint lives at `script/Deploy.s.sol`. It pre-computes the upcoming deployment addresses using `vm.computeCreateAddress`, deploys the Hub and IDRC implementations, wires them behind `ERC1967Proxy` proxies, and logs both the predicted and actual addresses. Provide the following environment variables before running a broadcast:

- `PRIVATE_KEY`: deployer private key

Run the script against a target RPC endpoint:

```bash
forge script script/Deploy.s.sol:Deploy --rpc-url <your_rpc_url> --broadcast
```

## Foundry Reference

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Deploy.s.sol:Deploy --rpc-url <your_rpc_url> --broadcast
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
