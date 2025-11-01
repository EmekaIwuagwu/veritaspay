# VeritasPay API Reference

**Complete API Documentation for Smart Contracts**

Version 1.0 | Last Updated: November 2025

---

## Table of Contents

1. [Overview](#overview)
2. [VeritasPayUSD](#veritaspayusd)
3. [HybridVault](#hybridvault)
4. [VPayProcessor](#vpaypayprocessor)
5. [VPayCompliance](#vpaycompliance)
6. [VPayBridgeHub](#vpaybridgehub)
7. [VPayTreasury](#vpaytreasury)
8. [VPayGovernance](#vpaygovernance)
9. [Events](#events)
10. [Error Codes](#error-codes)

---

## Overview

### Contract Addresses (Polygon Mainnet)

```javascript
const CONTRACTS = {
  VPUSD: "0x...",              // VeritasPayUSD
  VAULT: "0x...",              // HybridVault
  PROCESSOR: "0x...",          // VPayProcessor
  COMPLIANCE: "0x...",         // VPayCompliance
  PAYMASTER: "0x...",          // VPayPaymaster
  BRIDGE: "0x...",             // VPayBridgeHub
  TREASURY: "0x...",           // VPayTreasury
  GOVERNANCE: "0x..."          // VPayGovernance
};
```

### Network Information

| Network | Chain ID | RPC URL |
|---------|----------|---------|
| Polygon | 137 | https://polygon-rpc.com |
| Arbitrum | 42161 | https://arb1.arbitrum.io/rpc |
| Base | 8453 | https://mainnet.base.org |
| Ethereum | 1 | https://eth.llamarpc.com |

---

## VeritasPayUSD

Core ERC-20 stablecoin with payment extensions.

### Read Functions

#### `name() → string`
Returns the token name.
```solidity
function name() external view returns (string memory)
```
**Returns**: `"VeritasPay USD"`

#### `symbol() → string`
Returns the token symbol.
```solidity
function symbol() external view returns (string memory)
```
**Returns**: `"VPUSD"`

#### `decimals() → uint8`
Returns token decimals.
```solidity
function decimals() external view returns (uint8)
```
**Returns**: `18`

#### `totalSupply() → uint256`
Returns total supply.
```solidity
function totalSupply() external view returns (uint256)
```

#### `balanceOf(address account) → uint256`
Returns balance of account.
```solidity
function balanceOf(address account) external view returns (uint256)
```
**Parameters**:
- `account`: Address to check

#### `allowance(address owner, address spender) → uint256`
Returns allowance.
```solidity
function allowance(address owner, address spender) external view returns (uint256)
```

#### `calculatePaymentFee(uint256 amount) → uint256`
Calculates payment fee (tiered).
```solidity
function calculatePaymentFee(uint256 amount) public view returns (uint256 fee)
```
**Fee Structure**:
- < $100: 0.1%
- $100-$10,000: 0.05%
- > $10,000: 0.03%

**Example**:
```javascript
const fee = await vpusd.calculatePaymentFee(ethers.parseEther("1000"));
// Returns 0.5 VPUSD (0.05% of 1000)
```

#### `isFrozen(address user) → bool`
Checks if account is frozen.
```solidity
function isFrozen(address user) public view returns (bool frozen)
```

#### `getPayment(bytes32 paymentId) → Payment`
Gets payment details.
```solidity
function getPayment(bytes32 paymentId) external view returns (Payment memory payment)
```
**Returns**: Payment struct

### Write Functions

#### `transfer(address to, uint256 amount) → bool`
Standard ERC-20 transfer.
```solidity
function transfer(address to, uint256 amount) external returns (bool)
```

#### `approve(address spender, uint256 amount) → bool`
Approve spending.
```solidity
function approve(address spender, uint256 amount) external returns (bool)
```

#### `transferFrom(address from, address to, uint256 amount) → bool`
Transfer from approved address.
```solidity
function transferFrom(address from, address to, uint256 amount) external returns (bool)
```

#### `payWithMetadata(address to, uint256 amount, bytes calldata invoiceData) → bytes32`
Payment with metadata tracking.
```solidity
function payWithMetadata(address to, uint256 amount, bytes calldata invoiceData)
    external
    returns (bytes32 paymentId)
```
**Parameters**:
- `to`: Recipient address
- `amount`: Amount to send (in wei)
- `invoiceData`: ABI-encoded `(bytes32 invoiceId, string currency)`

**Example**:
```javascript
const invoiceData = ethers.AbiCoder.defaultAbiCoder().encode(
  ["bytes32", "string"],
  [ethers.id("INV-001"), "USD"]
);

const tx = await vpusd.payWithMetadata(
  recipientAddress,
  ethers.parseEther("100"),
  invoiceData
);
```

#### `batchPay(address[] calldata recipients, uint256[] calldata amounts)`
Batch payments (payroll).
```solidity
function batchPay(address[] calldata recipients, uint256[] calldata amounts) external
```
**Parameters**:
- `recipients`: Array of addresses (max 100)
- `amounts`: Array of amounts (must match recipients length)

**Example**:
```javascript
await vpusd.batchPay(
  ["0x...", "0x...", "0x..."],
  [ethers.parseEther("1000"), ethers.parseEther("1500"), ethers.parseEther("2000")]
);
```

#### `scheduledPayment(address to, uint256 amount, uint256 executeAt) → bytes32`
Schedule future payment.
```solidity
function scheduledPayment(address to, uint256 amount, uint256 executeAt)
    external
    returns (bytes32 paymentId)
```
**Parameters**:
- `to`: Recipient
- `amount`: Amount
- `executeAt`: Unix timestamp (must be future)

#### `executeScheduledPayment(bytes32 paymentId)`
Execute a scheduled payment.
```solidity
function executeScheduledPayment(bytes32 paymentId) external
```
**Requirements**:
- Current time >= executeAt
- Payment still pending

### Admin Functions

#### `mint(address to, uint256 amount)`
Mint new tokens (MINTER_ROLE only).
```solidity
function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE)
```

#### `burn(address from, uint256 amount)`
Burn tokens.
```solidity
function burn(address from, uint256 amount) external
```

#### `freezeAccount(address user, string calldata reason)`
Freeze account (COMPLIANCE_ROLE only).
```solidity
function freezeAccount(address user, string calldata reason) external onlyRole(COMPLIANCE_ROLE)
```

#### `unfreezeAccount(address user)`
Unfreeze account.
```solidity
function unfreezeAccount(address user) external onlyRole(COMPLIANCE_ROLE)
```

---

## HybridVault

Collateral management and algorithmic stabilization.

### Read Functions

#### `getReserveRatio() → uint256`
Current reserve ratio (in basis points).
```solidity
function getReserveRatio() public view returns (uint256 ratio)
```
**Example**: `15000` = 150%

#### `getVPUSDPrice() → uint256`
Current VPUSD price from oracles.
```solidity
function getVPUSDPrice() public view returns (uint256 price)
```
**Returns**: Price in 18 decimals (1e18 = $1.00)

#### `getCollateralValue(address token, uint256 amount) → uint256`
Calculate collateral value in USD.
```solidity
function getCollateralValue(address token, uint256 amount) public view returns (uint256 value)
```

#### `getPosition(uint256 positionId) → Position`
Get position details.
```solidity
function getPosition(uint256 positionId) external view returns (Position memory position)
```

#### `isPositionHealthy(uint256 positionId) → bool`
Check if position is adequately collateralized.
```solidity
function isPositionHealthy(uint256 positionId) public view returns (bool healthy)
```

### Write Functions

#### `deposit(address collateralToken, uint256 collateralAmount, uint256 vpusdAmount) → uint256`
Deposit collateral and mint VPUSD.
```solidity
function deposit(address collateralToken, uint256 collateralAmount, uint256 vpusdAmount)
    external
    returns (uint256 positionId)
```
**Example**:
```javascript
// Deposit $1000 USDC, mint 666 VPUSD (150% CR)
await vault.deposit(
  USDC_ADDRESS,
  ethers.parseUnits("1000", 6), // USDC has 6 decimals
  ethers.parseEther("666")
);
```

#### `withdraw(uint256 positionId, uint256 collateralAmount, uint256 vpusdAmount)`
Withdraw collateral and burn VPUSD.
```solidity
function withdraw(uint256 positionId, uint256 collateralAmount, uint256 vpusdAmount) external
```

#### `executeStabilization()`
Execute algorithmic stabilization.
```solidity
function executeStabilization() external onlyRole(STABILIZER_ROLE)
```

#### `liquidate(uint256 positionId)`
Liquidate undercollateralized position.
```solidity
function liquidate(uint256 positionId) external
```
**Incentive**: 5% bonus on collateral

---

## VPayProcessor

Merchant payment processing.

### Read Functions

#### `getMerchant(address merchant) → Merchant`
Get merchant information.
```solidity
function getMerchant(address merchant) external view returns (Merchant memory merchantInfo)
```

#### `getMerchantStats(address merchant) → MerchantStats`
Get merchant statistics.
```solidity
function getMerchantStats(address merchant) external view returns (MerchantStats memory stats)
```

#### `getInvoice(bytes32 invoiceId) → Invoice`
Get invoice details.
```solidity
function getInvoice(bytes32 invoiceId) external view returns (Invoice memory invoice)
```

#### `calculateMerchantFee(uint256 amount) → uint256`
Calculate merchant processing fee (0.3%).
```solidity
function calculateMerchantFee(uint256 amount) public view returns (uint256 fee)
```

### Write Functions

#### `registerMerchant(string calldata businessName, string calldata country, FiatSettlementPreference settlement)`
Register as merchant.
```solidity
function registerMerchant(
    string calldata businessName,
    string calldata country,
    FiatSettlementPreference settlement
) external
```
**Settlement Options**:
- `0`: CRYPTO
- `1`: FIAT_INSTANT
- `2`: FIAT_DAILY
- `3`: FIAT_WEEKLY

**Example**:
```javascript
await processor.registerMerchant("My Store", "US", 1); // FIAT_INSTANT
```

#### `createInvoice(uint256 amount, string calldata currency, uint256 expiresAt) → bytes32`
Create invoice.
```solidity
function createInvoice(uint256 amount, string calldata currency, uint256 expiresAt)
    external
    returns (bytes32 invoiceId)
```

#### `payInvoice(bytes32 invoiceId)`
Pay an invoice.
```solidity
function payInvoice(bytes32 invoiceId) external
```

#### `processPayment(address merchant, uint256 amount, bytes32 invoiceId, string calldata currency) → bytes32`
Process merchant payment.
```solidity
function processPayment(
    address merchant,
    uint256 amount,
    bytes32 invoiceId,
    string calldata currency
) external returns (bytes32 paymentId)
```

#### `batchPayments(address[] calldata recipients, uint256[] calldata amounts, string calldata purpose) → bytes32[]`
Batch payments (payroll/remittances).
```solidity
function batchPayments(
    address[] calldata recipients,
    uint256[] calldata amounts,
    string calldata purpose
) external returns (bytes32[] memory paymentIds)
```

---

## VPayCompliance

KYC/AML and compliance.

### Read Functions

#### `isVerified(address user) → bool`
Check if user is KYC verified.
```solidity
function isVerified(address user) external view returns (bool verified)
```

#### `isSanctioned(address user) → bool`
Check if address is sanctioned.
```solidity
function isSanctioned(address user) external view returns (bool sanctioned)
```

#### `getRiskScore(address user) → uint8`
Get user risk score (0-100).
```solidity
function getRiskScore(address user) external view returns (uint8 riskScore)
```

#### `analyzeTransaction(address sender, address recipient, uint256 amount) → TransactionRisk`
Analyze transaction risk.
```solidity
function analyzeTransaction(address sender, address recipient, uint256 amount)
    external
    view
    returns (TransactionRisk memory risk)
```

**Returns**:
```solidity
struct TransactionRisk {
    uint8 riskScore;
    bool requiresReview;
    string[] flags;
}
```

### Write Functions

#### `verifyUser(address user) → bool`
Verify user (COMPLIANCE_OFFICER_ROLE).
```solidity
function verifyUser(address user) external onlyRole(COMPLIANCE_OFFICER_ROLE) returns (bool)
```

#### `addToSanctionList(address user, string calldata reason)`
Add to sanction list.
```solidity
function addToSanctionList(address user, string calldata reason)
    external
    onlyRole(COMPLIANCE_OFFICER_ROLE)
```

#### `flagTransaction(bytes32 txId, string calldata reason)`
Flag suspicious transaction.
```solidity
function flagTransaction(bytes32 txId, string calldata reason)
    external
    onlyRole(COMPLIANCE_OFFICER_ROLE)
```

---

## VPayBridgeHub

Cross-chain payment infrastructure.

### Read Functions

#### `getBestRoute(uint256 destinationChain, uint256 amount, RoutePreference preference) → BridgeRoute`
Get optimal bridge route.
```solidity
function getBestRoute(uint256 destinationChain, uint256 amount, RoutePreference preference)
    external
    view
    returns (BridgeRoute memory route)
```
**Preferences**:
- `0`: FASTEST
- `1`: CHEAPEST
- `2`: MOST_RELIABLE

### Write Functions

#### `bridgePayment(...) → bytes32`
Bridge payment to another chain.
```solidity
function bridgePayment(
    uint256 destinationChain,
    address recipient,
    uint256 amount,
    BridgeProtocol preferredProtocol,
    bytes calldata paymentMetadata
) external payable returns (bytes32 bridgeId)
```
**Protocols**:
- `0`: LAYERZERO
- `1`: AXELAR
- `2`: WORMHOLE
- `3`: CCIP

**Example**:
```javascript
// Bridge 1000 VPUSD from Polygon to Arbitrum
await bridge.bridgePayment(
  42161, // Arbitrum chain ID
  recipientAddress,
  ethers.parseEther("1000"),
  0, // LayerZero
  "0x", // No extra metadata
  { value: ethers.parseEther("0.01") } // Native token for bridge fee
);
```

---

## VPayTreasury

Revenue and staking.

### Read Functions

#### `getAPY(uint256 lockPeriod) → uint256`
Get APY for lock period.
```solidity
function getAPY(uint256 lockPeriod) external view returns (uint256 apy)
```
**Lock Periods**:
- 30 days: 500 bps (5%)
- 90 days: 1000 bps (10%)
- 180 days: 1500 bps (15%)
- 365 days: 2500 bps (25%)

#### `getTotalRevenue() → uint256`
Get total revenue collected.
```solidity
function getTotalRevenue() external view returns (uint256)
```

### Write Functions

#### `stakeVPUSD(uint256 amount, uint256 lockPeriod) → uint256`
Stake VPUSD for rewards.
```solidity
function stakeVPUSD(uint256 amount, uint256 lockPeriod)
    external
    returns (uint256 stakingId)
```
**Example**:
```javascript
const LOCK_365_DAYS = 365 * 24 * 60 * 60;
await treasury.stakeVPUSD(ethers.parseEther("10000"), LOCK_365_DAYS);
```

#### `unstake(uint256 stakingId)`
Unstake and claim rewards.
```solidity
function unstake(uint256 stakingId) external
```

#### `claimRewards(uint256 stakingId)`
Claim rewards without unstaking.
```solidity
function claimRewards(uint256 stakingId) external
```

---

## Events

### VeritasPayUSD Events

```solidity
event PaymentProcessed(
    bytes32 indexed paymentId,
    address indexed sender,
    address indexed recipient,
    uint256 amount,
    bytes32 invoiceId,
    string currency
);

event BatchPayment(address indexed sender, uint256 recipientCount, uint256 totalAmount);

event AccountFrozen(address indexed account, string reason);

event AccountUnfrozen(address indexed account);
```

### VPayProcessor Events

```solidity
event MerchantRegistered(address indexed merchant, string businessName, string country);

event PaymentProcessed(
    bytes32 indexed paymentId,
    address indexed payer,
    address indexed merchant,
    uint256 amount,
    bytes32 invoiceId,
    uint256 fee
);

event InvoiceCreated(bytes32 indexed invoiceId, address indexed merchant, uint256 amount, string currency);

event InvoicePaid(bytes32 indexed invoiceId, address indexed payer, uint256 amount);
```

### VPayBridgeHub Events

```solidity
event PaymentBridged(
    bytes32 indexed bridgeId,
    address indexed sender,
    address indexed recipient,
    uint256 sourceChain,
    uint256 destChain,
    uint256 amount,
    BridgeProtocol protocol
);

event BridgeCompleted(bytes32 indexed bridgeId, uint256 timestamp);

event BridgeFailed(bytes32 indexed bridgeId, string reason);
```

---

## Error Codes

### Common Errors

| Error | Code | Description |
|-------|------|-------------|
| `Insufficient balance` | - | Balance too low |
| `Invalid address` | - | Address is zero or invalid |
| `Sender frozen` | - | Account is frozen |
| `Recipient frozen` | - | Recipient account frozen |
| `Not compliant` | - | Failed KYC/AML check |
| `Exceeds daily cap` | - | Over daily limit |
| `Invalid amount` | - | Amount is zero or negative |
| `Already registered` | - | Merchant already exists |
| `Not a merchant` | - | Address not registered |
| `Position unhealthy` | - | Below collateralization threshold |
| `Circuit breaker active` | - | System paused due to volatility |

---

## Code Examples

### Complete Integration Example

```javascript
const { ethers } = require("ethers");

// Setup
const provider = new ethers.JsonRpcProvider("https://polygon-rpc.com");
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

// Load contracts
const vpusd = new ethers.Contract(VPUSD_ADDRESS, VPUSD_ABI, wallet);
const processor = new ethers.Contract(PROCESSOR_ADDRESS, PROCESSOR_ABI, wallet);

// 1. Register as merchant
await processor.registerMerchant("My Store", "US", 1);

// 2. Create invoice
const expiresAt = Math.floor(Date.now() / 1000) + 86400; // 24 hours
const tx = await processor.createInvoice(
  ethers.parseEther("99.99"),
  "USD",
  expiresAt
);
const receipt = await tx.wait();
const invoiceId = // Extract from events

// 3. Customer pays (from customer's wallet)
await vpusd.approve(PROCESSOR_ADDRESS, ethers.parseEther("99.99"));
await processor.payInvoice(invoiceId);

// 4. Receive settlement (automatic based on preference)
```

---

**For more examples, see the [Developer Guide](./DEV_DOCS.md)**
