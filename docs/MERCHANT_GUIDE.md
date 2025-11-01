# VeritasPay Merchant Guide

**How to Accept VPUSD Payments for Your Business**

Version 1.0 | Last Updated: November 2025

---

## Table of Contents

1. [Why Accept VPUSD?](#why-accept-vpusd)
2. [Getting Started](#getting-started)
3. [Merchant Registration](#merchant-registration)
4. [Accepting Payments](#accepting-payments)
5. [Settlement Options](#settlement-options)
6. [Integration Methods](#integration-methods)
7. [Pricing & Fees](#pricing--fees)
8. [Compliance & KYC](#compliance--kyc)
9. [Support](#support)

---

## Why Accept VPUSD?

### 💰 Lower Fees
- **Credit Cards**: 2.9% + $0.30 per transaction
- **PayPal International**: 3.9% + fixed fee
- **Bank Wire**: $25-$45 per transfer
- **VeritasPay**: **0.3%** flat fee

**Example**: On a $1,000 sale
- Credit card fee: **$29.30**
- VeritasPay fee: **$3.00**
- **You save**: $26.30 (90% savings!)

### ⚡ Instant Settlement
- **Traditional**: 2-5 business days
- **VeritasPay**: 30 seconds to your wallet
- **Your cash flow**: Improved dramatically

### 🌍 Global Reach
- Accept payments from 180+ countries
- No currency conversion headaches
- No international transaction fees
- 24/7/365 availability

### 🔒 Security Benefits
- No chargebacks (irreversible transactions)
- Reduced fraud risk
- Cryptographic security
- No stored payment data = PCI DSS compliance easier

### 📊 Additional Benefits
- Lower merchant account fees
- No monthly minimums
- No setup fees
- Real-time reporting
- API integration available

---

## Getting Started

### Step 1: Create a Wallet

You'll need a cryptocurrency wallet to receive VPUSD payments.

**Recommended Wallets**:
- **MetaMask** (Browser extension) - https://metamask.io
- **Trust Wallet** (Mobile) - https://trustwallet.com
- **Coinbase Wallet** (Multi-platform) - https://wallet.coinbase.com

**Setup MetaMask** (5 minutes):
1. Install MetaMask browser extension
2. Click "Create a new wallet"
3. Secure your recovery phrase (12 words) - **CRITICAL: Keep this safe!**
4. Create a password
5. Your wallet is ready!

### Step 2: Add Polygon Network

VPUSD operates on Polygon for low fees:

1. Open MetaMask
2. Click network dropdown (top)
3. Click "Add Network"
4. Enter Polygon details:

```
Network Name: Polygon Mainnet
RPC URL: https://polygon-rpc.com
Chain ID: 137
Currency Symbol: MATIC
Block Explorer: https://polygonscan.com
```

5. Click "Save"

### Step 3: Get Your Wallet Address

1. Open MetaMask
2. Click your account name at top
3. Click the address to copy (starts with 0x...)
4. This is your receiving address - save it!

Example: `0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb`

---

## Merchant Registration

### Option 1: Simple Registration (No Code)

**Via VeritasPay Dashboard** (Coming Soon):
1. Go to https://merchant.veritaspay.io
2. Click "Register as Merchant"
3. Fill in business details:
   - Business Name
   - Country
   - Business Type
   - Website (optional)
   - Wallet Address
4. Complete KYC verification
5. Choose settlement preference
6. Done! You can now accept payments

### Option 2: Programmatic Registration

If you're integrating via code:

```javascript
// Using Web3
const { ethers } = require("ethers");

async function registerMerchant() {
  // Connect wallet
  const provider = new ethers.JsonRpcProvider("https://polygon-rpc.com");
  const wallet = new ethers.Wallet(YOUR_PRIVATE_KEY, provider);

  // Load contract
  const processorAddress = "0x..."; // VPayProcessor address
  const processorABI = [...]; // ABI from docs
  const processor = new ethers.Contract(processorAddress, processorABI, wallet);

  // Register
  const tx = await processor.registerMerchant(
    "My Online Store",      // Business name
    "US",                    // Country code
    1                        // Settlement: 1 = FIAT_INSTANT
  );

  await tx.wait();
  console.log("Registered successfully!");
}
```

### Settlement Preferences

Choose how you want to receive funds:

| Option | Description | Time | Fee |
|--------|-------------|------|-----|
| **CRYPTO** (0) | Receive VPUSD directly | Instant | 0% |
| **FIAT_INSTANT** (1) | Convert to fiat immediately | 5-10 min | 0.5% |
| **FIAT_DAILY** (2) | Batch daily at 11:59 PM UTC | Next day | 0.3% |
| **FIAT_WEEKLY** (3) | Batch weekly on Friday | End of week | 0.2% |

**Recommendation**:
- E-commerce with low margins → FIAT_DAILY (0.3%)
- High volume → CRYPTO then convert yourself
- Need immediate cash → FIAT_INSTANT (0.5%)

---

## Accepting Payments

### Method 1: Payment Links (No Code Required)

**Create a payment link**:
1. Go to VeritasPay Merchant Dashboard
2. Click "Create Payment Link"
3. Enter amount and description
4. Get shareable link: `https://pay.veritaspay.io/inv/abc123`
5. Share with customer via email, SMS, or website

**Example**:
```
Invoice for: Website Development
Amount: $1,500 VPUSD
Payment Link: https://pay.veritaspay.io/inv/abc123
Expires: 24 hours
```

### Method 2: Payment Button (Simple HTML)

Add to your website:

```html
<!-- Add this to your page -->
<button onclick="payWithVeritasPay()">Pay with VeritasPay</button>

<script src="https://cdn.veritaspay.io/checkout.js"></script>
<script>
function payWithVeritasPay() {
  VeritasPay.checkout({
    merchantAddress: '0xYourWalletAddress',
    amount: '99.99',
    currency: 'USD',
    description: 'Product Name',
    onSuccess: function(paymentId) {
      alert('Payment successful! ID: ' + paymentId);
      // Fulfill order
    },
    onError: function(error) {
      alert('Payment failed: ' + error);
    }
  });
}
</script>
```

### Method 3: Create Invoice Programmatically

```javascript
async function createInvoice(amount, currency, expiresInHours) {
  const processor = new ethers.Contract(
    processorAddress,
    processorABI,
    wallet
  );

  // Create invoice
  const expiresAt = Math.floor(Date.now() / 1000) + (expiresInHours * 3600);

  const tx = await processor.createInvoice(
    ethers.parseEther(amount.toString()),
    currency,
    expiresAt
  );

  const receipt = await tx.wait();

  // Get invoice ID from event
  const event = receipt.logs.find(log =>
    processor.interface.parseLog(log)?.name === "InvoiceCreated"
  );

  const invoiceId = processor.interface.parseLog(event).args.invoiceId;

  console.log("Invoice created:", invoiceId);
  return invoiceId;
}

// Usage
const invoiceId = await createInvoice(99.99, "USD", 24);
// Share invoice ID with customer
```

### Method 4: Direct Payment Processing

For immediate payment processing:

```javascript
async function processCustomerPayment(
  customerAddress,
  amount,
  invoiceId
) {
  const processor = new ethers.Contract(
    processorAddress,
    processorABI,
    wallet
  );

  const tx = await processor.processPayment(
    wallet.address,  // Your merchant address
    ethers.parseEther(amount.toString()),
    invoiceId,
    "USD"
  );

  const receipt = await tx.wait();

  // Payment successful!
  console.log("Payment received:", receipt.hash);

  // Fulfill order here
  fulfillOrder(invoiceId);
}
```

---

## Settlement Options

### Option 1: Keep as VPUSD (0% Fee)

**Benefits**:
- No conversion fees
- Hold stable USD value
- Use for business expenses
- Convert later when needed

**How to use**:
- Pay suppliers who accept crypto
- Hold as stable reserve
- Convert to other crypto
- Send to exchange when ready to cash out

### Option 2: Auto-Convert to Fiat

**Instant Settlement** (0.5% fee):
```javascript
// Set settlement preference to FIAT_INSTANT
await processor.updateSettlementPreference(1);
```

Your VPUSD is automatically converted to your local currency and sent to your bank account within 5-10 minutes.

**Daily Batch** (0.3% fee):
```javascript
// Set settlement preference to FIAT_DAILY
await processor.updateSettlementPreference(2);
```

All payments received during the day are batched at 11:59 PM UTC and sent to your bank the next business day.

**Weekly Batch** (0.2% fee):
```javascript
// Set settlement preference to FIAT_WEEKLY
await processor.updateSettlementPreference(3);
```

Payments are batched weekly every Friday and sent to your bank.

### Banking Integration

**Supported Countries** (for fiat offramp):
- United States (ACH, Wire)
- European Union (SEPA)
- United Kingdom (Faster Payments)
- Canada (Interac)
- Australia (BPAY, POLi)
- More regions coming soon

**Setup Bank Account**:
1. Go to Merchant Dashboard
2. Navigate to "Settlement Settings"
3. Click "Add Bank Account"
4. Enter bank details
5. Verify micro-deposits (1-2 days)
6. Activate auto-settlement

---

## Integration Methods

### E-Commerce Platforms

#### **Shopify** (Plugin Available)

1. Install VeritasPay from Shopify App Store
2. Connect your wallet
3. Set pricing in USD (auto-converts to VPUSD)
4. Enable at checkout
5. Done!

**Features**:
- Automatic VPUSD price calculation
- Order management integration
- Inventory sync
- Refund handling

#### **WooCommerce** (WordPress)

1. Download VeritasPay plugin: https://wordpress.org/plugins/veritaspay
2. Install in WordPress Admin → Plugins → Add New → Upload
3. Activate plugin
4. Go to WooCommerce → Settings → Payments
5. Enable VeritasPay
6. Enter merchant wallet address
7. Save changes

**Configuration**:
```php
// Settings in WooCommerce
Merchant Wallet: 0xYourWalletAddress
Settlement Preference: FIAT_INSTANT
Accepted Currencies: USD, EUR, GBP
Network: Polygon
```

#### **Custom Integration** (API)

```javascript
// Example: Node.js/Express checkout
app.post('/checkout', async (req, res) => {
  const { items, customerEmail } = req.body;

  // Calculate total
  const total = items.reduce((sum, item) => sum + item.price, 0);

  // Create invoice
  const invoiceId = await createInvoice(total, "USD", 24);

  // Send to customer
  await sendInvoiceEmail(customerEmail, invoiceId, total);

  res.json({
    success: true,
    invoiceId,
    paymentUrl: `https://pay.veritaspay.io/inv/${invoiceId}`
  });
});

// Webhook for payment confirmation
app.post('/webhook/payment-confirmed', async (req, res) => {
  const { invoiceId, paymentId, amount } = req.body;

  // Verify signature (important!)
  if (!verifyWebhookSignature(req)) {
    return res.status(401).send('Unauthorized');
  }

  // Fulfill order
  await fulfillOrder(invoiceId);

  res.sendStatus(200);
});
```

### Point of Sale (POS)

**In-Person Payments**:

1. **QR Code Payment**:
   - Generate QR code with payment details
   - Customer scans with mobile wallet
   - Payment instant
   - Receipt generated

2. **NFC/Tap to Pay** (Coming Soon):
   - Customer taps phone
   - Payment processed
   - No hardware needed

**Example QR Code Generation**:
```javascript
const QRCode = require('qrcode');

async function generatePaymentQR(amount, invoiceId) {
  const paymentData = {
    merchant: merchantAddress,
    amount: amount,
    invoiceId: invoiceId,
    network: 'polygon'
  };

  const qrCode = await QRCode.toDataURL(JSON.stringify(paymentData));
  return qrCode; // Display this image
}
```

---

## Pricing & Fees

### Transaction Fees

| Payment Type | VeritasPay Fee | Traditional Fee | Savings |
|--------------|----------------|-----------------|---------|
| Domestic Card | 0.3% | 2.9% + $0.30 | 89% |
| International Card | 0.3% | 3.9% + $0.30 | 92% |
| Bank Transfer | 0.3% | $25-45 | 99% |
| PayPal | 0.3% | 2.9%-4.4% | 87-93% |

### Settlement Fees

| Method | Fee | When |
|--------|-----|------|
| CRYPTO (keep as VPUSD) | 0% | Instant |
| FIAT_INSTANT | 0.5% | 5-10 minutes |
| FIAT_DAILY | 0.3% | Next business day |
| FIAT_WEEKLY | 0.2% | End of week |

### No Hidden Fees

- ✅ No setup fees
- ✅ No monthly fees
- ✅ No minimum volume
- ✅ No cancellation fees
- ✅ No PCI compliance fees
- ✅ No chargeback fees (they don't exist!)

### Volume Discounts

| Monthly Volume | Standard Fee | Discounted Fee |
|----------------|--------------|----------------|
| $0 - $50K | 0.30% | 0.30% |
| $50K - $250K | 0.30% | 0.25% |
| $250K - $1M | 0.30% | 0.20% |
| $1M+ | 0.30% | 0.15% (negotiate) |

**Contact sales@veritaspay.io for volume pricing**

---

## Compliance & KYC

### Why KYC is Required

To comply with regulations and prevent fraud, all merchants must complete KYC (Know Your Customer) verification.

### Verification Levels

**Level 1 - Basic** (< $10K/month):
- Business name
- Country
- Email verification
- Approval: Instant

**Level 2 - Standard** ($10K - $100K/month):
- Level 1 requirements +
- Government ID
- Business registration documents
- Proof of address
- Approval: 1-2 business days

**Level 3 - Enhanced** (> $100K/month):
- Level 2 requirements +
- Bank statements
- Business bank account
- Video verification call
- Approval: 3-5 business days

### Required Documents

**For Sole Proprietors**:
- Government-issued ID (passport, driver's license)
- Proof of address (utility bill, bank statement)
- Tax ID number (SSN, EIN)

**For Companies**:
- Business registration certificate
- Articles of incorporation
- Tax ID (EIN)
- Director/beneficial owner IDs
- Proof of business address

### Data Security

- All documents encrypted
- Stored with industry-leading compliance provider
- GDPR compliant
- You can request data deletion anytime

---

## Merchant Dashboard

### Features

**Overview**:
- Today's revenue
- This month's revenue
- Total transactions
- Average transaction size

**Transactions**:
- Real-time transaction list
- Search and filter
- Export to CSV
- Download receipts

**Analytics**:
- Revenue charts
- Customer geography
- Payment methods
- Peak hours

**Invoicing**:
- Create invoices
- View pending invoices
- Invoice templates
- Recurring invoices

**Settings**:
- Update business info
- Settlement preferences
- Bank account management
- API keys
- Webhooks

---

## Support

### Getting Help

**Documentation**:
- Developer Docs: https://docs.veritaspay.io
- API Reference: https://api.veritaspay.io/docs
- Video Tutorials: https://youtube.com/veritaspay

**Contact Support**:
- Email: merchant-support@veritaspay.io
- Live Chat: merchant.veritaspay.io (bottom right)
- Phone: +1 (555) VPAY-HELP
- Response time: < 4 hours

**Community**:
- Discord: https://discord.gg/veritaspay
- Telegram: https://t.me/veritaspay_merchants
- Twitter: @VeritasPayBiz

### Office Hours

**Live Support**:
- Monday - Friday: 9 AM - 6 PM EST
- Saturday: 10 AM - 2 PM EST
- Sunday: Closed

**Emergency Support** (24/7):
- For critical issues: emergency@veritaspay.io
- Phone: +1 (555) VPAY-911

---

## FAQs

### Q: Do I need to hold cryptocurrency?

**A:** No! You can choose instant fiat settlement and receive regular currency to your bank account. VPUSD is just the payment method.

### Q: What if the customer doesn't have VPUSD?

**A:** They can buy it instantly on our payment page using credit card, debit card, or bank transfer. They don't need to "learn crypto" - it's handled automatically.

### Q: Are there chargebacks?

**A:** No! This is one of the biggest benefits. Transactions are final and irreversible, eliminating chargeback fraud.

### Q: What happens if I get a refund request?

**A:** You can process refunds manually through the dashboard. Since there are no forced chargebacks, you maintain control.

### Q: Is this legal in my country?

**A:** VeritasPay operates in compliance with local regulations. Check our coverage map: https://veritaspay.io/coverage

We support: US, EU, UK, Canada, Australia, and 150+ other countries.

### Q: How do I handle taxes?

**A:** You report revenue the same as any other payment method. We provide detailed transaction exports for your accountant. Consult a tax professional for specific advice.

### Q: What if the price of crypto crashes?

**A:** VPUSD is a stablecoin pegged to $1 USD. It doesn't fluctuate like Bitcoin or Ethereum. $100 VPUSD = $100 USD, always.

### Q: Can I accept other cryptocurrencies?

**A:** Currently, we only support VPUSD for the best merchant experience (stable pricing, low fees). Other cryptos may be added later.

---

## Success Stories

### "We cut payment processing costs by 90%"
*"As an online retailer with international customers, payment fees were killing our margins. VeritasPay reduced our costs from 3.5% to 0.3%, saving us $40K annually."*
— Sarah M., E-commerce Store Owner

### "Cash flow improved dramatically"
*"Getting paid in 30 seconds instead of 3 days changed everything. No more waiting for payment processor settlements."*
— James L., Freelance Developer

### "Zero chargebacks saved our business"
*"We were losing $15K/month to fraudulent chargebacks. With VeritasPay's irreversible transactions, that's completely eliminated."*
— Maria G., Digital Services Provider

---

## Next Steps

### Ready to Start?

1. **Register** at https://merchant.veritaspay.io
2. **Complete KYC** verification (1-2 days)
3. **Integrate** using your preferred method
4. **Start accepting** VPUSD payments!

### Need Help Deciding?

**Schedule a demo**: https://veritaspay.io/demo
**Talk to sales**: sales@veritaspay.io
**Compare pricing**: https://veritaspay.io/pricing

---

**Welcome to the future of payments! 🚀**

*VeritasPay - Lower fees. Faster settlement. Global reach.*
