const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

/**
 * Integration Tests for VeritasPay Protocol
 * Tests complete user flows across multiple contracts
 */
describe("VeritasPay Integration Tests", function () {
    async function deployFullProtocolFixture() {
        const [deployer, user1, user2, merchant, liquidator] = await ethers.getSigners();

        // 1. Deploy VPUSD
        const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
        const vpusd = await upgrades.deployProxy(
            VeritasPayUSD,
            [deployer.address, deployer.address, 10],
            { initializer: "initialize", kind: "uups" }
        );

        // 2. Deploy Mock Oracle
        const MockOracle = await ethers.getContractFactory("MockOracle");
        const collateralOracle = await MockOracle.deploy("USDC/USD", 8, 100000000n); // $1.00

        // 3. Deploy HybridVault
        const HybridVault = await ethers.getContractFactory("HybridVault");
        const vault = await upgrades.deployProxy(
            HybridVault,
            [deployer.address, await vpusd.getAddress(), 15000, 17500],
            { initializer: "initialize", kind: "uups" }
        );

        // 4. Deploy VPayCompliance
        const VPayCompliance = await ethers.getContractFactory("VPayCompliance");
        const compliance = await upgrades.deployProxy(
            VPayCompliance,
            [deployer.address, ethers.parseUnits("10000", 18)],
            { initializer: "initialize", kind: "uups" }
        );

        // 5. Deploy VPayProcessor
        const VPayProcessor = await ethers.getContractFactory("VPayProcessor");
        const processor = await upgrades.deployProxy(
            VPayProcessor,
            [deployer.address, await vpusd.getAddress(), deployer.address, 30],
            { initializer: "initialize", kind: "uups" }
        );

        // 6. Deploy VPayBridgeHub
        const VPayBridgeHub = await ethers.getContractFactory("VPayBridgeHub");
        const bridge = await upgrades.deployProxy(
            VPayBridgeHub,
            [deployer.address, await vpusd.getAddress(), 5, ethers.parseUnits("100000", 18)],
            { initializer: "initialize", kind: "uups" }
        );

        // Setup roles
        const MINTER_ROLE = await vpusd.MINTER_ROLE();
        await vpusd.grantRole(MINTER_ROLE, await vault.getAddress());
        await vpusd.grantRole(MINTER_ROLE, await bridge.getAddress());
        await vpusd.grantRole(MINTER_ROLE, deployer.address);

        // Setup compliance on processor
        await processor.setComplianceOracle(await compliance.getAddress());

        // Add collateral token to vault
        await vault.addCollateralToken(
            await vpusd.getAddress(), // Using VPUSD as mock collateral for testing
            0, // TIER1
            await collateralOracle.getAddress()
        );

        // Verify users with compliance
        const COMPLIANCE_ROLE = await compliance.COMPLIANCE_OFFICER_ROLE();
        await compliance.grantRole(COMPLIANCE_ROLE, deployer.address);
        await compliance.verifyUser(user1.address);
        await compliance.verifyUser(user2.address);
        await compliance.verifyUser(merchant.address);

        // Mint initial balances
        await vpusd.mint(user1.address, ethers.parseUnits("10000", 18));
        await vpusd.mint(user2.address, ethers.parseUnits("10000", 18));

        return {
            vpusd, vault, compliance, processor, bridge, collateralOracle,
            deployer, user1, user2, merchant, liquidator
        };
    }

    describe("End-to-End: Deposit → Mint → Payment", function () {
        it("Should complete full deposit to merchant payment flow", async function () {
            const { vpusd, vault, processor, compliance, user1, merchant, deployer } =
                await loadFixture(deployFullProtocolFixture);

            // Step 1: User deposits collateral and mints VPUSD
            const depositAmount = ethers.parseUnits("1000", 18);
            const mintAmount = ethers.parseUnits("500", 18);

            await vpusd.connect(user1).approve(await vault.getAddress(), depositAmount);
            await vault.connect(user1).deposit(
                await vpusd.getAddress(),
                depositAmount,
                mintAmount
            );

            const userBalance = await vpusd.balanceOf(user1.address);
            expect(userBalance).to.equal(ethers.parseUnits("9500", 18)); // 10000 - 1000 + 500

            // Step 2: Merchant registers
            await processor.connect(merchant).registerMerchant("Test Shop", "US", 0); // CRYPTO settlement

            // Step 3: User pays merchant
            const paymentAmount = ethers.parseUnits("100", 18);
            await vpusd.connect(user1).approve(await processor.getAddress(), paymentAmount);

            await expect(processor.connect(user1).processPayment(
                merchant.address,
                paymentAmount,
                ethers.encodeBytes32String("INV001"),
                "USD"
            )).to.emit(processor, "PaymentProcessed");

            // Verify merchant received payment (minus fee)
            const merchantBalance = await vpusd.balanceOf(merchant.address);
            expect(merchantBalance).to.be.gt(0n);
        });
    });

    describe("End-to-End: Invoice Creation → Payment", function () {
        it("Should complete invoice creation and payment flow", async function () {
            const { vpusd, processor, user1, merchant } =
                await loadFixture(deployFullProtocolFixture);

            // Step 1: Merchant registers
            await processor.connect(merchant).registerMerchant("Invoice Shop", "UK", 0);

            // Step 2: Merchant creates invoice
            const invoiceAmount = ethers.parseUnits("250", 18);
            const expiresAt = Math.floor(Date.now() / 1000) + 86400; // 24 hours

            const tx = await processor.connect(merchant).createInvoice(
                invoiceAmount,
                "USD",
                expiresAt
            );
            const receipt = await tx.wait();
            const event = receipt.logs.find(log => {
                try {
                    return processor.interface.parseLog(log)?.name === "InvoiceCreated";
                } catch { return false; }
            });
            const invoiceId = processor.interface.parseLog(event).args.invoiceId;

            // Step 3: User pays invoice
            await vpusd.connect(user1).approve(await processor.getAddress(), invoiceAmount);

            await expect(processor.connect(user1).payInvoice(invoiceId))
                .to.emit(processor, "InvoicePaid");

            // Verify invoice is paid
            const invoice = await processor.getInvoice(invoiceId);
            expect(invoice.status).to.equal(1n); // PAID
        });
    });

    describe("End-to-End: Cross-Chain Bridge", function () {
        it("Should initiate cross-chain payment", async function () {
            const { vpusd, bridge, user1, user2 } =
                await loadFixture(deployFullProtocolFixture);

            const bridgeAmount = ethers.parseUnits("500", 18);
            const destChain = 137; // Polygon

            // Approve bridge to burn tokens
            await vpusd.connect(user1).approve(await bridge.getAddress(), bridgeAmount);

            await expect(bridge.connect(user1).bridgePayment(
                destChain,
                user2.address,
                bridgeAmount,
                0, // LAYERZERO
                "0x"
            )).to.emit(bridge, "PaymentBridged");

            // Verify tokens were burned
            const balanceAfter = await vpusd.balanceOf(user1.address);
            expect(balanceAfter).to.equal(ethers.parseUnits("9500", 18));
        });
    });

    describe("End-to-End: Batch Payments (Payroll)", function () {
        it("Should process batch payments", async function () {
            const { vpusd, processor, user1, user2, merchant, deployer } =
                await loadFixture(deployFullProtocolFixture);

            // Prepare recipients
            const recipients = [user2.address, merchant.address];
            const amounts = [
                ethers.parseUnits("100", 18),
                ethers.parseUnits("200", 18)
            ];
            const totalAmount = ethers.parseUnits("300", 18);

            // Verify all recipients
            const compliance = await ethers.getContractAt(
                "VPayCompliance",
                await processor.complianceOracle()
            );

            await vpusd.connect(user1).approve(await processor.getAddress(), totalAmount);

            await expect(processor.connect(user1).batchPayments(
                recipients,
                amounts,
                "Monthly Payroll"
            )).to.emit(processor, "BatchPaymentsExecuted");

            // Verify recipients received funds
            const user2Balance = await vpusd.balanceOf(user2.address);
            expect(user2Balance).to.be.gt(ethers.parseUnits("10000", 18)); // Initial + payment
        });
    });

    describe("End-to-End: Liquidation Flow", function () {
        it("Should liquidate underwater position", async function () {
            const { vpusd, vault, collateralOracle, user1, liquidator, deployer } =
                await loadFixture(deployFullProtocolFixture);

            // Step 1: User creates a highly leveraged position (150% ratio, at the edge)
            const depositAmount = ethers.parseUnits("1500", 18);
            const mintAmount = ethers.parseUnits("1000", 18); // Exactly 150% collateral ratio

            await vpusd.connect(user1).approve(await vault.getAddress(), depositAmount);
            await vault.connect(user1).deposit(
                await vpusd.getAddress(),
                depositAmount,
                mintAmount
            );

            // Step 2: Price drops significantly, making position underwater (below 130%)
            // At $0.70, collateral value = 1500 * 0.70 = $1050
            // Required for 130% = 1000 * 1.3 = $1300
            // Position is now underwater
            await collateralOracle.updatePrice(70000000n); // $0.70 (30% drop)

            // Step 3: Liquidator gets VPUSD for liquidation
            await vpusd.mint(liquidator.address, mintAmount);
            await vpusd.connect(liquidator).approve(await vault.getAddress(), mintAmount);

            // Step 4: Liquidate
            await expect(vault.connect(liquidator).liquidate(1))
                .to.emit(vault, "PositionLiquidated");

            // Verify position is cleared
            const position = await vault.getPosition(1);
            expect(position.vpusdMinted).to.equal(0n);
        });
    });

    describe("Compliance Integration", function () {
        it("Should block payments from sanctioned users", async function () {
            const { vpusd, processor, compliance, user1, merchant, deployer } =
                await loadFixture(deployFullProtocolFixture);

            // Register merchant
            await processor.connect(merchant).registerMerchant("Shop", "US", 0);

            // Sanction user
            await compliance.addToSanctionList(user1.address, "Test sanction");

            // Try to pay - should fail
            const paymentAmount = ethers.parseUnits("100", 18);
            await vpusd.connect(user1).approve(await processor.getAddress(), paymentAmount);

            await expect(processor.connect(user1).processPayment(
                merchant.address,
                paymentAmount,
                ethers.encodeBytes32String("INV002"),
                "USD"
            )).to.be.revertedWith("Payer sanctioned");
        });
    });
});
