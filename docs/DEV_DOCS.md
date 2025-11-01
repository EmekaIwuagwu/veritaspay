# VeritasPay Developer Guide

**Complete Integration Guide for Developers**

Version 1.0 | Last Updated: November 2025

---

## Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [Smart Contract Architecture](#smart-contract-architecture)
4. [Integration Patterns](#integration-patterns)
5. [SDK Usage](#sdk-usage)
6. [Testing](#testing)
7. [Deployment](#deployment)
8. [Security Best Practices](#security-best-practices)
9. [Troubleshooting](#troubleshooting)

---

## Introduction

Welcome to the VeritasPay Developer Guide! This comprehensive guide will help you integrate VPUSD into your application, whether you're building a payment processor, DeFi protocol, or cross-border payment solution.

### What You'll Learn

- How to interact with VPUSD smart contracts
- Integration patterns for common use cases
- SDK usage and API calls
- Testing strategies
- Deployment best practices

### Prerequisites

```bash
- Node.js >= 18.x
- npm >= 9.x
- Basic understanding of Ethereum/EVM
- Familiarity with Solidity
- MetaMask or similar wallet
```

---

## Getting Started

### 1. Installation

```bash
# Clone the repository
git clone https://github.com/EmekaIwuagwu/veritaspay.git
cd veritaspay

# Install dependencies
npm install

# Copy environment template
cp .env.example .env

# Configure your environment
nano .env
```

### 2. Environment Configuration

Edit `.env` file:

```bash
# Network RPC URLs
POLYGON_RPC_URL=https://polygon-rpc.com
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc

# Your private key (NEVER commit this!)
DEPLOYER_PRIVATE_KEY=your_private_key_here

# Contract addresses (after deployment)
VPUSD_ADDRESS=0x...
VAULT_ADDRESS=0x...
PROCESSOR_ADDRESS=0x...
```

### 3. Compile Contracts

```bash
# Using Hardhat
npx hardhat compile

# Using Foundry
forge build
```

### 4. Run Tests

```bash
# Run all tests
npm test

# Run specific test file
npx hardhat test test/unit/VeritasPayUSD.test.js

# Run with gas reporting
REPORT_GAS=true npm test

# Run with coverage
npm run test:coverage
```

---

## Smart Contract Architecture

### Core Contracts Overview

```
VeritasPay Ecosystem
│
├── VeritasPayUSD.sol          # Main stablecoin token
├── HybridVault.sol            # Collateral management
├── VPayProcessor.sol          # Payment processing
├── VPayCompliance.sol         # KYC/AML
├── VPayPaymaster.sol          # Gasless transactions
├── VPayBridgeHub.sol          # Cross-chain
├── VPayTreasury.sol           # Revenue management
└── VPayGovernance.sol         # Governance
```

### Contract Addresses (Polygon Mainnet)

```javascript
const CONTRACTS = {
  VPUSD: "0x...",           // VeritasPayUSD token
  VAULT: "0x...",           // HybridVault
  PROCESSOR: "0x...",       // VPayProcessor
  COMPLIANCE: "0x...",      // VPayCompliance
  BRIDGE: "0x...",          // VPayBridgeHub
  TREASURY: "0x...",        // VPayTreasury
  GOVERNANCE: "0x..."       // VPayGovernance
};
```

---

## Integration Patterns

### Pattern 1: Basic Token Transfer

```javascript
const { ethers } = require("ethers");

// Connect to provider
const provider = new ethers.JsonRpcProvider(process.env.POLYGON_RPC_URL);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

// Load VPUSD contract
const vpusdABI = require("./artifacts/contracts/core/VeritasPayUSD.sol/VeritasPayUSD.json");
const vpusd = new ethers.Contract(CONTRACTS.VPUSD, vpusdABI.abi, wallet);

// Transfer VPUSD
async function transferVPUSD(to, amount) {
  const tx = await vpusd.transfer(to, ethers.parseEther(amount.toString()));
  await tx.wait();
  console.log(`Transferred ${amount} VPUSD to ${to}`);
  return tx.hash;
}

// Usage
await transferVPUSD("0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb", 100);
```

### Pattern 2: Payment with Metadata

```javascript
async function payWithInvoice(recipient, amount, invoiceId, currency) {
  // Encode invoice data
  const invoiceData = ethers.AbiCoder.defaultAbiCoder().encode(
    ["bytes32", "string"],
    [ethers.id(invoiceId), currency]
  );

  // Execute payment
  const tx = await vpusd.payWithMetadata(
    recipient,
    ethers.parseEther(amount.toString()),
    invoiceData
  );

  const receipt = await tx.wait();

  // Get payment ID from events
  const event = receipt.logs.find(log => {
    try {
      return vpusd.interface.parseLog(log).name === "PaymentProcessed";
    } catch {
      return false;
    }
  });

  const paymentId = vpusd.interface.parseLog(event).args.paymentId;
  console.log(`Payment ID: ${paymentId}`);

  return paymentId;
}

// Usage
await payWithInvoice(
  "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
  500,
  "INV-2024-001",
  "USD"
);
```

### Pattern 3: Batch Payments (Payroll)

```javascript
async function processBatchPayroll(employees, salaries) {
  // Validate inputs
  if (employees.length !== salaries.length) {
    throw new Error("Arrays must have same length");
  }

  // Convert salaries to wei
  const amounts = salaries.map(s => ethers.parseEther(s.toString()));

  // Calculate total
  const total = amounts.reduce((a, b) => a + b, 0n);

  // Check balance
  const balance = await vpusd.balanceOf(wallet.address);
  if (balance < total) {
    throw new Error(`Insufficient balance. Need ${ethers.formatEther(total)}, have ${ethers.formatEther(balance)}`);
  }

  // Execute batch payment
  const tx = await vpusd.batchPay(employees, amounts);
  const receipt = await tx.wait();

  console.log(`Paid ${employees.length} employees, total: ${ethers.formatEther(total)} VPUSD`);
  return receipt;
}

// Usage
const employees = [
  "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
  "0x5A0b54D5dc17e0AadC383d2db43B0a0D3E029c4c",
  "0x9876543210987654321098765432109876543210"
];

const salaries = [5000, 4500, 6000]; // in VPUSD

await processBatchPayroll(employees, salaries);
```

### Pattern 4: Merchant Integration

```javascript
// Register as merchant
async function registerAsMerchant(businessName, country, settlementPref) {
  const processor = new ethers.Contract(
    CONTRACTS.PROCESSOR,
    processorABI.abi,
    wallet
  );

  // Settlement preferences: 0=CRYPTO, 1=FIAT_INSTANT, 2=FIAT_DAILY, 3=FIAT_WEEKLY
  const tx = await processor.registerMerchant(
    businessName,
    country,
    settlementPref
  );

  await tx.wait();
  console.log(`Registered merchant: ${businessName}`);
}

// Create invoice
async function createInvoice(amount, currency, expiresInHours) {
  const processor = new ethers.Contract(
    CONTRACTS.PROCESSOR,
    processorABI.abi,
    wallet
  );

  const expiresAt = Math.floor(Date.now() / 1000) + (expiresInHours * 3600);

  const tx = await processor.createInvoice(
    ethers.parseEther(amount.toString()),
    currency,
    expiresAt
  );

  const receipt = await tx.wait();

  // Extract invoice ID from events
  const event = receipt.logs.find(log => {
    try {
      return processor.interface.parseLog(log).name === "InvoiceCreated";
    } catch {
      return false;
    }
  });

  const invoiceId = processor.interface.parseLog(event).args.invoiceId;
  return invoiceId;
}

// Process customer payment
async function acceptPayment(customerAddress, amount, invoiceId) {
  const processor = new ethers.Contract(
    CONTRACTS.PROCESSOR,
    processorABI.abi,
    wallet
  );

  const tx = await processor.processPayment(
    wallet.address, // merchant
    ethers.parseEther(amount.toString()),
    invoiceId,
    "USD"
  );

  await tx.wait();
  console.log(`Payment received: ${amount} VPUSD`);
}

// Usage
await registerAsMerchant("My Online Store", "US", 1); // FIAT_INSTANT
const invoiceId = await createInvoice(99.99, "USD", 24); // 24 hour expiry
```

### Pattern 5: Cross-Chain Payment

```javascript
async function bridgePayment(destChainId, recipient, amount, protocol) {
  const bridge = new ethers.Contract(
    CONTRACTS.BRIDGE,
    bridgeABI.abi,
    wallet
  );

  // Protocol: 0=LAYERZERO, 1=AXELAR, 2=WORMHOLE, 3=CCIP
  const paymentMetadata = ethers.AbiCoder.defaultAbiCoder().encode(
    ["string", "uint256"],
    ["cross-border-payment", Date.now()]
  );

  // Approve VPUSD for burning
  await vpusd.approve(CONTRACTS.BRIDGE, ethers.parseEther(amount.toString()));

  // Execute bridge
  const tx = await bridge.bridgePayment(
    destChainId,
    recipient,
    ethers.parseEther(amount.toString()),
    protocol,
    paymentMetadata,
    { value: ethers.parseEther("0.01") } // Native token for bridge fees
  );

  const receipt = await tx.wait();

  // Get bridge ID
  const event = receipt.logs.find(log => {
    try {
      return bridge.interface.parseLog(log).name === "PaymentBridged";
    } catch {
      return false;
    }
  });

  const bridgeId = bridge.interface.parseLog(event).args.bridgeId;
  console.log(`Bridge initiated. ID: ${bridgeId}`);

  return bridgeId;
}

// Usage - Bridge from Polygon to Arbitrum
await bridgePayment(
  42161, // Arbitrum chain ID
  "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
  1000,
  0 // LayerZero
);
```

### Pattern 6: Gasless Transaction (ERC-4337)

```javascript
async function sponsorGaslessPayment(userAddress, recipient, amount) {
  const paymaster = new ethers.Contract(
    CONTRACTS.PAYMASTER,
    paymasterABI.abi,
    wallet
  );

  // Estimate gas for the payment transaction
  const gasEstimate = await vpusd.estimateGas.transfer(recipient, ethers.parseEther(amount.toString()));
  const gasPrice = (await provider.getFeeData()).gasPrice;

  // Calculate VPUSD fee
  const vpusdFee = await paymaster.calculateVPUSDFee(gasEstimate, gasPrice);

  console.log(`Gas will cost ${ethers.formatEther(vpusdFee)} VPUSD`);

  // User approves VPUSD to paymaster
  // This would be done by the user's wallet
  // await vpusd.connect(userWallet).approve(CONTRACTS.PAYMASTER, vpusdFee);

  // Sponsor the transaction
  const tx = await paymaster.sponsorWithVPUSD(
    userAddress,
    gasEstimate,
    gasPrice
  );

  await tx.wait();
  console.log("Gasless transaction sponsored!");
}
```

### Pattern 7: Staking for Yield

```javascript
async function stakeVPUSD(amount, lockPeriodDays) {
  const treasury = new ethers.Contract(
    CONTRACTS.TREASURY,
    treasuryABI.abi,
    wallet
  );

  // Lock periods in seconds
  const LOCK_PERIODS = {
    30: 30 * 24 * 60 * 60,   // 30 days - 5% APY
    90: 90 * 24 * 60 * 60,   // 90 days - 10% APY
    180: 180 * 24 * 60 * 60, // 180 days - 15% APY
    365: 365 * 24 * 60 * 60  // 365 days - 25% APY
  };

  const lockPeriod = LOCK_PERIODS[lockPeriodDays];
  if (!lockPeriod) {
    throw new Error("Invalid lock period. Choose 30, 90, 180, or 365 days");
  }

  // Get APY
  const apy = await treasury.getAPY(lockPeriod);
  console.log(`Staking ${amount} VPUSD for ${lockPeriodDays} days at ${apy / 100}% APY`);

  // Approve treasury to spend VPUSD
  await vpusd.approve(CONTRACTS.TREASURY, ethers.parseEther(amount.toString()));

  // Stake
  const tx = await treasury.stakeVPUSD(
    ethers.parseEther(amount.toString()),
    lockPeriod
  );

  const receipt = await tx.wait();

  // Get staking ID from events
  const event = receipt.logs.find(log => {
    try {
      return treasury.interface.parseLog(log).name === "Staked";
    } catch {
      return false;
    }
  });

  const stakingId = treasury.interface.parseLog(event).args.stakingId;
  console.log(`Staking ID: ${stakingId}`);

  return stakingId;
}

// Unstake after lock period
async function unstakeVPUSD(stakingId) {
  const treasury = new ethers.Contract(
    CONTRACTS.TREASURY,
    treasuryABI.abi,
    wallet
  );

  const tx = await treasury.unstake(stakingId);
  await tx.wait();

  console.log("Unstaked successfully!");
}

// Usage
const stakingId = await stakeVPUSD(10000, 365); // Stake 10,000 VPUSD for 1 year
// ... wait for lock period ...
await unstakeVPUSD(stakingId);
```

---

## SDK Usage

### TypeScript SDK (Coming Soon)

```typescript
import { VeritasPay, Chain } from '@veritaspay/sdk';

// Initialize SDK
const veritasPay = new VeritasPay({
  chain: Chain.POLYGON,
  privateKey: process.env.PRIVATE_KEY,
  rpcUrl: process.env.POLYGON_RPC_URL
});

// Simple payment
await veritasPay.pay({
  to: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
  amount: 100,
  currency: "USD"
});

// Merchant operations
await veritasPay.merchant.register({
  businessName: "My Store",
  country: "US"
});

const invoice = await veritasPay.merchant.createInvoice({
  amount: 99.99,
  expiresInHours: 24
});
```

---

## Testing

### Unit Testing Example

```javascript
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("VeritasPayUSD - Custom Tests", function () {
  let vpusd, owner, user1, user2;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
    vpusd = await upgrades.deployProxy(
      VeritasPayUSD,
      [owner.address, owner.address, 10],
      { initializer: "initialize", kind: "uups" }
    );
  });

  it("Should process payment correctly", async function () {
    // Mint tokens to user1
    const MINTER_ROLE = await vpusd.MINTER_ROLE();
    await vpusd.grantRole(MINTER_ROLE, owner.address);
    await vpusd.mint(user1.address, ethers.parseEther("1000"));

    // Create payment
    const invoiceData = ethers.AbiCoder.defaultAbiCoder().encode(
      ["bytes32", "string"],
      [ethers.id("INV-001"), "USD"]
    );

    await expect(
      vpusd.connect(user1).payWithMetadata(
        user2.address,
        ethers.parseEther("100"),
        invoiceData
      )
    ).to.emit(vpusd, "PaymentProcessed");

    // Check balances (accounting for fees)
    const fee = await vpusd.calculatePaymentFee(ethers.parseEther("100"));
    const netAmount = ethers.parseEther("100") - fee;

    expect(await vpusd.balanceOf(user2.address)).to.equal(netAmount);
  });
});
```

### Integration Testing

```javascript
describe("Full Payment Flow", function () {
  it("Should complete end-to-end payment", async function () {
    // 1. User deposits collateral to vault
    // 2. Vault mints VPUSD
    // 3. User pays merchant
    // 4. Merchant receives payment
    // 5. Fee goes to treasury
  });
});
```

---

## Deployment

### Deploy to Testnet

```bash
# Deploy all contracts
npx hardhat run scripts/deployment/deploy-testnet.js --network mumbai

# Verify on Polygonscan
npx hardhat verify --network mumbai <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>
```

### Deploy to Mainnet

```bash
# IMPORTANT: Double-check all parameters
npx hardhat run scripts/deployment/deploy-mainnet.js --network polygon

# Verify all contracts
npm run verify:all
```

### Custom Deployment Script

```javascript
const { ethers, upgrades } = require("hardhat");

async function deploy() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying with:", deployer.address);

  // Deploy VPUSD
  const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
  const vpusd = await upgrades.deployProxy(
    VeritasPayUSD,
    [deployer.address, deployer.address, 10],
    { initializer: "initialize", kind: "uups" }
  );

  console.log("VPUSD deployed to:", await vpusd.getAddress());

  // Deploy more contracts...
}

deploy().catch((error) => {
  console.error(error);
  process.exit(1);
});
```

---

## Security Best Practices

### 1. Private Key Management

```bash
# NEVER commit private keys
# Use environment variables
# Consider using:
# - AWS Secrets Manager
# - HashiCorp Vault
# - Hardware wallets (Ledger/Trezor)
```

### 2. Input Validation

```javascript
// Always validate inputs
function validateAddress(address) {
  if (!ethers.isAddress(address)) {
    throw new Error("Invalid address");
  }
}

function validateAmount(amount) {
  if (amount <= 0) {
    throw new Error("Amount must be positive");
  }
}
```

### 3. Error Handling

```javascript
async function safeTransfer(to, amount) {
  try {
    validateAddress(to);
    validateAmount(amount);

    const tx = await vpusd.transfer(to, ethers.parseEther(amount.toString()));
    await tx.wait();

    return { success: true, hash: tx.hash };
  } catch (error) {
    console.error("Transfer failed:", error);
    return { success: false, error: error.message };
  }
}
```

### 4. Gas Optimization

```javascript
// Use batch operations when possible
async function optimizedMultiTransfer(recipients, amounts) {
  // Instead of multiple transfers, use batchPay
  return await vpusd.batchPay(recipients, amounts);
}
```

---

## Troubleshooting

### Common Issues

#### Issue 1: "Insufficient Balance"

```javascript
// Check balance before transaction
const balance = await vpusd.balanceOf(wallet.address);
const amount = ethers.parseEther("100");

if (balance < amount) {
  console.error(`Insufficient balance. Have ${ethers.formatEther(balance)}, need ${ethers.formatEther(amount)}`);
  return;
}
```

#### Issue 2: "Transaction Reverted"

```javascript
// Use try-catch and check revert reason
try {
  const tx = await vpusd.transfer(to, amount);
  await tx.wait();
} catch (error) {
  if (error.reason) {
    console.error("Revert reason:", error.reason);
  }
  console.error("Full error:", error);
}
```

#### Issue 3: "Gas Estimation Failed"

```javascript
// Manually set gas limit
const tx = await vpusd.transfer(to, amount, {
  gasLimit: 100000
});
```

### Debug Mode

```javascript
// Enable verbose logging
const vpusd = new ethers.Contract(
  CONTRACTS.VPUSD,
  vpusdABI.abi,
  wallet
);

vpusd.on("*", (event) => {
  console.log("Event:", event);
});
```

---

## API Endpoints

### REST API (Coming Soon)

```bash
# Get token info
GET /api/v1/token/info

# Get user balance
GET /api/v1/balance/:address

# Get transaction history
GET /api/v1/transactions/:address

# Create payment
POST /api/v1/payments
{
  "to": "0x...",
  "amount": "100",
  "currency": "USD"
}
```

---

## Resources

### Official Links
- **Website**: https://veritaspay.io
- **GitHub**: https://github.com/EmekaIwuagwu/veritaspay
- **Documentation**: https://docs.veritaspay.io
- **Discord**: https://discord.gg/veritaspay

### Community
- **Developer Forum**: https://forum.veritaspay.io
- **Telegram**: https://t.me/veritaspay_dev
- **Twitter**: @VeritasPayDev

### Support
- **Email**: dev-support@veritaspay.io
- **Office Hours**: Wednesdays 2-4pm UTC on Discord

---

## Appendix

### Gas Cost Reference

| Operation | Estimated Gas | Cost (@ 50 gwei) |
|-----------|--------------|------------------|
| Transfer | ~50,000 | ~$0.10 |
| PayWithMetadata | ~100,000 | ~$0.20 |
| BatchPay (10) | ~500,000 | ~$1.00 |
| Bridge Payment | ~200,000 | ~$0.40 |

### Contract ABIs

All contract ABIs are available in:
```
artifacts/contracts/**/*.json
```

---

**Need Help?** Join our developer Discord or email dev-support@veritaspay.io

**Happy Building! 🚀**
