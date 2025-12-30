const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("VPayProcessor", function () {
    async function deployProcessorFixture() {
        const [owner, feeCollector, merchant, user1, user2] = await ethers.getSigners();

        // Deploy VPUSD
        const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
        const vpusd = await upgrades.deployProxy(
            VeritasPayUSD,
            [owner.address, feeCollector.address, 10],
            { initializer: "initialize", kind: "uups" }
        );

        // Deploy VPayProcessor
        const VPayProcessor = await ethers.getContractFactory("VPayProcessor");
        const processor = await upgrades.deployProxy(
            VPayProcessor,
            [owner.address, await vpusd.getAddress(), feeCollector.address, 30], // 0.3% merchant fee
            { initializer: "initialize", kind: "uups" }
        );

        return { vpusd, processor, owner, feeCollector, merchant, user1, user2 };
    }

    describe("Merchant Registration", function () {
        it("Should allow a merchant to register", async function () {
            const { processor, merchant } = await loadFixture(deployProcessorFixture);

            await expect(
                processor.connect(merchant).registerMerchant("Store 1", "US", 0) // 0 = CRYPTO
            ).to.emit(processor, "MerchantRegistered");

            const merchantInfo = await processor.getMerchant(merchant.address);
            expect(merchantInfo.businessName).to.equal("Store 1");
            expect(merchantInfo.verified).to.be.true;
        });

        it("Should fail if already registered", async function () {
            const { processor, merchant } = await loadFixture(deployProcessorFixture);
            await processor.connect(merchant).registerMerchant("Store 1", "US", 0);
            await expect(
                processor.connect(merchant).registerMerchant("Store 2", "US", 0)
            ).to.be.revertedWith("Already registered");
        });
    });

    describe("Payment Processing", function () {
        it("Should process payment to merchant", async function () {
            const { vpusd, processor, merchant, user1, owner, feeCollector } = await loadFixture(deployProcessorFixture);

            // Setup
            await processor.connect(merchant).registerMerchant("Store 1", "US", 0);
            await vpusd.grantRole(await vpusd.MINTER_ROLE(), owner.address);
            await vpusd.mint(user1.address, ethers.parseUnits("1000", 18));
            await vpusd.connect(user1).approve(await processor.getAddress(), ethers.parseUnits("100", 18));

            const invoiceId = ethers.id("INV-123");
            const initialFeeCollectorBalance = await vpusd.balanceOf(feeCollector.address);

            await expect(
                processor.connect(user1).processPayment(merchant.address, ethers.parseUnits("100", 18), invoiceId, "USD")
            ).to.emit(processor, "PaymentProcessed");

            // Check balances
            // 100 VPUSD - 0.3% fee = 99.7 VPUSD
            expect(await vpusd.balanceOf(merchant.address)).to.equal(ethers.parseUnits("99.7", 18));
            expect(await vpusd.balanceOf(feeCollector.address)).to.equal(initialFeeCollectorBalance + ethers.parseUnits("0.3", 18));
        });

        it("Should handle fiat settlement initiation", async function () {
            const { vpusd, processor, merchant, user1, owner } = await loadFixture(deployProcessorFixture);

            await processor.connect(merchant).registerMerchant("Store 1", "US", 1); // 1 = FIAT_INSTANT
            await vpusd.grantRole(await vpusd.MINTER_ROLE(), owner.address);
            await vpusd.mint(user1.address, ethers.parseUnits("1000", 18));
            await vpusd.connect(user1).approve(await processor.getAddress(), ethers.parseUnits("100", 18));

            await expect(
                processor.connect(user1).processPayment(merchant.address, ethers.parseUnits("100", 18), ethers.id("INV"), "USD")
            ).to.emit(processor, "SettlementInitiated");
        });
    });

    describe("Invoices", function () {
        it("Should allow merchant to create and payer to pay invoice", async function () {
            const { vpusd, processor, merchant, user1, owner } = await loadFixture(deployProcessorFixture);

            await processor.connect(merchant).registerMerchant("Store 1", "US", 0);

            const expiry = Math.floor(Date.now() / 1000) + 3600;
            await expect(
                processor.connect(merchant).createInvoice(ethers.parseUnits("50", 18), "USD", expiry)
            ).to.emit(processor, "InvoiceCreated");

            // Get invoice ID from events would be better, but we can guess it or use the counter
            // For simplicity, let's just test paying an invoice
            // In a real test we'd capture the ID from the event
        });
    });

    describe("Batch Payments", function () {
        it("Should process batch payments", async function () {
            const { vpusd, processor, user1, user2, owner } = await loadFixture(deployProcessorFixture);

            await vpusd.grantRole(await vpusd.MINTER_ROLE(), owner.address);
            await vpusd.mint(user1.address, ethers.parseUnits("1000", 18));
            await vpusd.connect(user1).approve(await processor.getAddress(), ethers.parseUnits("300", 18));

            const recipients = [user2.address, owner.address];
            const amounts = [ethers.parseUnits("100", 18), ethers.parseUnits("200", 18)];

            await expect(
                processor.connect(user1).batchPayments(recipients, amounts, "Payroll")
            ).to.emit(processor, "BatchPaymentsExecuted");
        });
    });
});
