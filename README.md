# IDRC Protocol - Smart Contract System

A decentralized protocol for tokenizing Indonesian Rupiah (IDR) bonds with yield distribution mechanisms built on blockchain technology using Foundry framework.

## Table of Contents

- [Overview](#overview)
- [System Architecture](#system-architecture)
- [Core Contracts](#core-contracts)
- [Smart Contract Details](#smart-contract-details)
- [Deployment](#deployment)
- [Testing](#testing)
- [Development](#development)
- [Security Features](#security-features)

## Overview

The IDRC Protocol is a sophisticated DeFi system that allows users to:
- Subscribe to tokenized bonds using IDRX (Indonesian Rupiah stablecoin)
- Receive IDRC tokens representing their bond positions
- Automatically earn proportional rewards from bond coupons/maturity
- Redeem their positions back to IDRX

### Key Features

- **Upgradeable Architecture**: All core contracts use UUPS proxy pattern for upgradeability
- **Role-Based Access Control**: Granular permissions for admin operations
- **Automatic Yield Distribution**: Proportional reward distribution to all token holders
- **1:1 Pegging**: IDRC tokens maintain 1:1 parity with IDRX collateral
- **Reentrancy Protection**: Guards against reentrancy attacks
- **Pausable Operations**: Emergency pause functionality for subscriptions/redemptions

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         IDRC Protocol                           │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│              │         │              │         │              │
│  IDRX Token  │◄────────┤     Hub      │────────►│     IDRC     │
│  (ERC20)     │         │  (Proxy)     │         │   (Proxy)    │
│              │         │              │         │              │
└──────────────┘         └──────┬───────┘         └──────┬───────┘
                                │                        │
                                │                        │
                                │                        │
                         ┌──────▼────────────────────────▼───┐
                         │                                   │
                         │    RewardDistributor (Proxy)      │
                         │                                   │
                         └───────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         User Flow                               │
└─────────────────────────────────────────────────────────────────┘

  User                Hub                IDRC           Reward
   │                  │                  │                │
   │──subscribe()────►│                  │                │
   │  (send IDRX)     │                  │                │
   │                  │──mintByHub()────►│                │
   │                                     │──update()─────►│
   │                                     │                │
   │◄─────receive IDRC tokens────────────┘                │
   │                                                      │
   │                  Admin                               │
   │                    │                                 │
   │                    │──injectReward()────────────────►│
   │                    │  (bond coupon)                  │
   │                                                      │
   │──claimReward()──────────────────────────────────────►│
   │◄─────receive IDRX rewards────────────────────────────┘
   │                                                      
   │──redeem()───────►│                                  
   │  (burn IDRC)     │──burnByHub()────►│ Burn Token             
   │◄──receive IDRX───┘                                
```

## Core Contracts

### 1. Hub (Hub.sol)
**Purpose**: Central contract managing subscriptions, redemptions, and asset custody

**Key Functions**:
- `requestSubscription(address tokenIn, uint256 amount)`: Deposit IDRX and receive IDRC tokens
- `requestRedemption(address tokenOut, uint256 shares)`: Burn IDRC and receive IDRX back
- `depositAsset(address tokenIn, uint256 amount)`: Admin deposits assets (yield from bonds)
- `withdrawAsset(address tokenOut, uint256 amount)`: Admin withdraws assets

**Roles**:
- `ADMIN_ROLE`: Can deposit/withdraw assets for yield management

**Storage Pattern**: Uses ERC-7201 namespaced storage (HubStorage library)

### 2. IDRC (IDRC.sol & IDRCv2.sol)
**Purpose**: Upgradeable ERC20 token representing user's bond position

**Key Functions**:
- `mintByHub(address to, uint256 amount)`: Hub-only minting
- `burnByHub(address from, uint256 amount)`: Hub-only burning
- `tvl()`: Returns total value locked (total supply)

**Special Features**:
- Hooks into RewardDistributor on every transfer/mint/burn via `_update()` override
- IDRCv2 adds `decimals()` override (returns 2) and `initializeV2()` for upgrades

### 3. RewardDistributor (RewardDistributor.sol)
**Purpose**: Manages proportional yield distribution to IDRC holders

**Key Functions**:
- `injectReward(uint256 amount)`: Admin injects bond yield (coupons/maturity)
- `earned(address account)`: View pending rewards for an account
- `claimReward()`: Users claim their accumulated rewards
- `updateReward(address account)`: Called by IDRC to update reward accounting

**Roles**:
- `ADMIN_MANAGER_ROLE`: Can inject rewards

**Reward Mechanism**:
```
rewardPerToken = (rewardAmount * 1e6) / totalSupply
userReward = userBalance * (rewardPerToken - lastUserRewardPerToken) / 1e6
```

### 4. IDRX (IDRX.sol)
**Purpose**: Mock stablecoin representing Indonesian Rupiah (for testnet)

**Features**:
- Standard ERC20 with configurable decimals
- Public `mint()` and `burn()` for testing purposes

## Smart Contract Details

### Deployment Order

The contracts have circular dependencies requiring deterministic address prediction:

```solidity
1. IDRX (simple ERC20, no proxy)
2. IDRC Implementation
3. Hub Implementation  
4. RewardDistributor Implementation
5. RewardDistributor Proxy (needs Hub + IDRC proxy addresses)
6. IDRC Proxy (needs Hub + Reward proxy addresses)
7. Hub Proxy (needs IDRX + IDRC proxy addresses)
```

### Upgrade Process

All upgradeable contracts (Hub, IDRC, RewardDistributor) use UUPS pattern:

```solidity
// Only owner can upgrade
function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
```

Example upgrade flow:
```solidity
// Deploy new implementation
IDRCv2 newImpl = new IDRCv2();

// Upgrade via owner
idrcProxy.upgradeToAndCall(address(newImpl), "");

// Optionally call reinitializer
idrcProxy.initializeV2(hubAddress, rewardAddress);
```

### Storage Patterns

**Hub**: Uses ERC-7201 namespaced storage to avoid collisions
```solidity
library HubStorage {
    struct MainStorage {
        IIDRC idrc;
        IRewardDistributor rewardDistributor;
        address asset;
        mapping(uint256 => uint256) prices;
        uint256 currentPriceId;
    }
    bytes32 private constant MAIN_STORAGE_LOCATION = 
        0x410db8097748b2adc18a3d9c7c820c57f308a38a62322863dc75caf59c7b4000;
}
```

**IDRC & RewardDistributor**: Use standard state variables with OpenZeppelin upgradeable base contracts

### Reward Distribution Algorithm

1. **Injection**: Admin deposits yield into RewardDistributor
   ```solidity
   rewardPerTokenStored += (rewardAmount * 1e6) / totalSupply
   ```

2. **Balance Changes**: IDRC calls `updateReward()` before any transfer/mint/burn
   ```solidity
   function _update(address from, address to, uint256 amount) internal override {
       if (from != address(0)) rewardDistributor.updateReward(from);
       if (to != address(0)) rewardDistributor.updateReward(to);
       super._update(from, to, amount);
   }
   ```

3. **Reward Calculation**:
   ```solidity
   pending = balance * (rewardPerTokenStored - userRewardPerTokenPaid[user]) / 1e6
   totalEarned = rewards[user] + pending
   ```

4. **Claiming**: User receives their accumulated rewards in IDRX

## Deployment

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install
```

### Configuration

Create `.env` file:
```bash
PRIVATE_KEY=your_private_key_here
ADMIN_MANAGER=0x...  # Address with admin privileges
RPC_URL=https://...  # Base Sepolia or other network
ETHERSCAN_API_KEY=your_api_key  # For verification
```

### Deploy to Testnet

```bash
# Deploy all contracts
forge script script/Deploy.s.sol --rpc-url base-sepolia --broadcast --verify

# Fill transaction data (if needed)
forge script script/FillTransact.s.sol --rpc-url base-sepolia --broadcast
```

### Upgrade Contracts

```bash
forge script script/Upgrades.s.sol --rpc-url base-sepolia --broadcast --verify
```

## Testing

### Run All Tests

```bash
# Run full test suite
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/Hub.t.sol

# Run specific test
forge test --match-test testRequestSubscriptionSuccess

# Generate gas report
forge test --gas-report

# Generate coverage
forge coverage
```

### Test Structure

```
test/
├── IDRC.t.sol              # Unit tests for IDRC token
├── Hub.t.sol               # Unit tests for Hub contract
├── RewardDistributor.t.sol # Unit tests for reward system
├── Integration.t.sol       # End-to-end integration tests
├── Deploy.t.sol            # Deployment script tests
├── Upgrades.t.sol          # Upgrade process tests
└── FillTransact.t.sol      # Transaction filling tests
```

### Test Coverage Areas

- ✅ Initialization and setup
- ✅ Subscription and redemption flows
- ✅ Minting and burning mechanisms
- ✅ Reward injection and distribution
- ✅ Reward claiming
- ✅ Access control (roles)
- ✅ Upgrade functionality
- ✅ Edge cases (zero amounts, insufficient balance, etc.)
- ✅ Multi-user scenarios
- ✅ Reentrancy protection

## Development

### Project Structure

```
contract/
├── src/
│   ├── Hub.sol                      # Main hub contract
│   ├── IDRC.sol                     # IDRC token v1
│   ├── IDRCv2.sol                   # IDRC token v2 (upgraded)
│   ├── IDRX.sol                     # Mock stablecoin
│   ├── RewardDistributor.sol        # Yield distribution
│   ├── interfaces/
│   │   ├── IHub.sol
│   │   ├── IIDRC.sol
│   │   └── IRewardDistributor.sol
│   └── libraries/
│       └── HubStorage.sol           # Namespaced storage
├── script/
│   ├── Deploy.s.sol                 # Deployment script
│   ├── Upgrades.s.sol               # Upgrade script
│   └── FillTransact.s.sol           # Transaction filler
├── test/                            # Comprehensive test suite
├── lib/                             # Dependencies (OpenZeppelin)
├── foundry.toml                     # Foundry configuration
└── remappings.txt                   # Import remappings
```

### Build

```bash
# Compile contracts
forge build

# Clean build artifacts
forge clean

# Format code
forge fmt
```

### Local Development

```bash
# Start local node
anvil

# Deploy to local
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

## Security Features

### Access Control

- **Hub**: `ADMIN_ROLE` for asset management
- **RewardDistributor**: `ADMIN_MANAGER_ROLE` for reward injection
- **IDRC**: Only Hub can mint/burn
- **Upgradeability**: Only owner can upgrade contracts

### Safety Mechanisms

1. **Reentrancy Guards**: All state-changing functions in Hub and RewardDistributor
2. **Pausable**: Hub can be paused in emergencies
3. **Input Validation**: Zero amount checks, zero address checks
4. **Safe Math**: Solidity 0.8.30+ with overflow protection
5. **SafeERC20**: Used for token transfers in RewardDistributor

### Known Limitations

- IDRX is a mock token with public mint/burn (not for production)
- Admin roles are powerful and should be controlled by multisig or governance
- Contract upgradeability requires trust in owner

## License

UNLICENSED - Private/Proprietary Code

## Technical Specifications

- **Solidity Version**: ^0.8.30
- **Framework**: Foundry
- **Proxy Pattern**: UUPS (ERC-1967)
- **Storage Pattern**: ERC-7201 (namespaced storage)
- **Dependencies**: 
  - OpenZeppelin Contracts v5.x
  - OpenZeppelin Contracts Upgradeable v5.x
  - Forge-std (testing)

## Contract Addresses

### Base Sepolia Testnet

**Proxy Contracts (User-Facing)**

| Contract | Address | Explorer |
|----------|---------|----------|
| Hub Proxy | `0xf2CCA756D7dE98d54ed00697EA8Cf50D71ea0Dd1` | [View on BaseScan](https://sepolia.basescan.org/address/0xf2CCA756D7dE98d54ed00697EA8Cf50D71ea0Dd1) |
| IDRC Proxy | `0xD3723bD07766d4993FBc936bEA1895227B556ea3` | [View on BaseScan](https://sepolia.basescan.org/address/0xD3723bD07766d4993FBc936bEA1895227B556ea3) |
| RewardDistributor Proxy | `0xA77C8059B011Ad0DB426623d1c1B985E53fdb7db` | [View on BaseScan](https://sepolia.basescan.org/address/0xA77C8059B011Ad0DB426623d1c1B985E53fdb7db) |

**Implementation Contracts**

| Contract | Address | Explorer |
|----------|---------|----------|
| Hub Implementation | `0x4CAa4eC854306F961A2e476B62c4e6dacb8C23eF` | [View on BaseScan](https://sepolia.basescan.org/address/0x4CAa4eC854306F961A2e476B62c4e6dacb8C23eF) |
| IDRC Implementation (v1) | `0x770d11A0583290f6B5BE500EE70720E3a3c01ea1` | [View on BaseScan](https://sepolia.basescan.org/address/0x770d11A0583290f6B5BE500EE70720E3a3c01ea1) |
| IDRC Implementation (v2) | `0x1BdF47D9736DDA87269D71d256F791FC418e31F6` | [View on BaseScan](https://sepolia.basescan.org/address/0x1BdF47D9736DDA87269D71d256F791FC418e31F6) |
| RewardDistributor Implementation | `0xd3D46E3bf01c947794Ce8aF52a30Fd6559a83a72` | [View on BaseScan](https://sepolia.basescan.org/address/0xd3D46E3bf01c947794Ce8aF52a30Fd6559a83a72) |

**Supporting Contracts**

| Contract | Address | Explorer |
|----------|---------|----------|
| IDRX Token (Mock Stablecoin) | `0x3E4c9e0a4F7F735401971dace92d18418da9c937` | [View on BaseScan](https://sepolia.basescan.org/address/0x3E4c9e0a4F7F735401971dace92d18418da9c937) |

### Network Information

- **Network**: Base Sepolia Testnet
- **Chain ID**: 84532
- **RPC URL**: https://sepolia.base.org
- **Block Explorer**: https://sepolia.basescan.org

### Important Notes

⚠️ **Always interact with Proxy addresses**, not implementation addresses. The proxy addresses forward calls to the implementation while maintaining state.

✅ **For mainnet deployment**, new addresses will be generated. The current addresses are for Base Sepolia testnet only.

🔄 **Upgradeability**: Implementation contracts can be upgraded by the owner through the proxy pattern. The IDRCv2 implementation is an example of an upgraded version.

## Additional Resources

- [Foundry Documentation](https://book.getfoundry.sh/)
- [OpenZeppelin Upgrades](https://docs.openzeppelin.com/upgrades-plugins/1.x/)
- [UUPS Proxy Pattern](https://eips.ethereum.org/EIPS/eip-1822)
- [ERC-7201 Namespaced Storage](https://eips.ethereum.org/EIPS/eip-7201)

## Support

For questions or issues, please contact the development team.
