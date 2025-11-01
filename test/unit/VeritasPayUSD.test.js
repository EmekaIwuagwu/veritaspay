const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("VeritasPayUSD", function () {
    async function deployVPUSDFixture() {
        const [owner, feeCollector, user1, user2, user3] = await ethers.getSigners();

        const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
        const vpusd = await upgrades.deployProxy(
            VeritasPayUSD,
            [owner.address, feeCollector.address, 10], // 0.1% base fee
            { initializer: "initialize", kind: "uups" }
        );

        return { vpusd, owner, feeCollector, user1, user2, user3 };
    }

    describe("Deployment", function () {
        it("Should set the correct name and symbol", async function () {
            const { vpusd } = await loadFixture(deployVPUSDFixture);
            expect(await vpusd.name()).to.equal("VeritasPay USD");
            expect(await vpusd.symbol()).to.equal("VPUSD");
        });

        it("Should set the correct fee collector", async function () {
            const { vpusd, feeCollector } = await loadFixture(deployVPUSDFixture);
            expect(await vpusd.feeCollector()).to.equal(feeCollector.address);
        });

        it("Should set the correct base payment fee", async function () {
            const { vpusd } = await loadFixture(deployVPUSDFixture);
            expect(await vpusd.basePaymentFeeBps()).to.equal(10);
        });

        it("Should grant admin role to owner", async function () {
            const { vpusd, owner } = await loadFixture(deployVPUSDFixture);
            const DEFAULT_ADMIN_ROLE = await vpusd.DEFAULT_ADMIN_ROLE();
            expect(await vpusd.hasRole(DEFAULT_ADMIN_ROLE, owner.address)).to.be.true;
        });
    });

    describe("Minting", function () {
        it("Should allow minter to mint tokens", async function () {
            const { vpusd, owner, user1 } = await loadFixture(deployVPUSDFixture);

            const MINTER_ROLE = await vpusd.MINTER_ROLE();
            await vpusd.grantRole(MINTER_ROLE, owner.address);

            await vpusd.mint(user1.address, ethers.parseEther("1000"));
            expect(await vpusd.balanceOf(user1.address)).to.equal(ethers.parseEther("1000"));
        });

        it("Should not allow non-minter to mint", async function () {
            const { vpusd, user1, user2 } = await loadFixture(deployVPUSDFixture);

            await expect(
                vpusd.connect(user1).mint(user2.address, ethers.parseEther("1000"))
            ).to.be.reverted;
        });

        it("Should not allow minting to frozen account", async function () {
            const { vpusd, owner, user1 } = await loadFixture(deployVPUSDFixture);

            const MINTER_ROLE = await vpusd.MINTER_ROLE();
            const COMPLIANCE_ROLE = await vpusd.COMPLIANCE_ROLE();
            await vpusd.grantRole(MINTER_ROLE, owner.address);
            await vpusd.grantRole(COMPLIANCE_ROLE, owner.address);

            await vpusd.freezeAccount(user1.address, "Test freeze");

            await expect(
                vpusd.mint(user1.address, ethers.parseEther("1000"))
            ).to.be.revertedWith("Recipient frozen");
        });
    });

    describe("Payment Features", function () {
        it("Should process payment with metadata", async function () {
            const { vpusd, owner, user1, user2 } = await loadFixture(deployVPUSDFixture);

            const MINTER_ROLE = await vpusd.MINTER_ROLE();
            await vpusd.grantRole(MINTER_ROLE, owner.address);
            await vpusd.mint(user1.address, ethers.parseEther("1000"));

            const invoiceId = ethers.id("INV-001");
            const invoiceData = ethers.AbiCoder.defaultAbiCoder().encode(
                ["bytes32", "string"],
                [invoiceId, "USD"]
            );

            await expect(
                vpusd.connect(user1).payWithMetadata(
                    user2.address,
                    ethers.parseEther("100"),
                    invoiceData
                )
            ).to.emit(vpusd, "PaymentProcessed");
        });

        it("Should calculate correct tiered fees", async function () {
            const { vpusd } = await loadFixture(deployVPUSDFixture);

            // < $100: 0.1%
            const fee1 = await vpusd.calculatePaymentFee(ethers.parseEther("50"));
            expect(fee1).to.equal(ethers.parseEther("50") * 10n / 10000n);

            // $100 - $10,000: 0.05%
            const fee2 = await vpusd.calculatePaymentFee(ethers.parseEther("1000"));
            expect(fee2).to.equal(ethers.parseEther("1000") * 5n / 10000n);

            // > $10,000: 0.03%
            const fee3 = await vpusd.calculatePaymentFee(ethers.parseEther("20000"));
            expect(fee3).to.equal(ethers.parseEther("20000") * 3n / 10000n);
        });

        it("Should process batch payments", async function () {
            const { vpusd, owner, user1, user2, user3 } = await loadFixture(deployVPUSDFixture);

            const MINTER_ROLE = await vpusd.MINTER_ROLE();
            await vpusd.grantRole(MINTER_ROLE, owner.address);
            await vpusd.mint(user1.address, ethers.parseEther("1000"));

            const recipients = [user2.address, user3.address];
            const amounts = [ethers.parseEther("100"), ethers.parseEther("200")];

            await expect(
                vpusd.connect(user1).batchPay(recipients, amounts)
            ).to.emit(vpusd, "BatchPayment");
        });
    });

    describe("Compliance", function () {
        it("Should freeze and unfreeze accounts", async function () {
            const { vpusd, owner, user1 } = await loadFixture(deployVPUSDFixture);

            const COMPLIANCE_ROLE = await vpusd.COMPLIANCE_ROLE();
            await vpusd.grantRole(COMPLIANCE_ROLE, owner.address);

            await vpusd.freezeAccount(user1.address, "AML check");
            expect(await vpusd.isFrozen(user1.address)).to.be.true;

            await vpusd.unfreezeAccount(user1.address);
            expect(await vpusd.isFrozen(user1.address)).to.be.false;
        });

        it("Should prevent frozen accounts from transferring", async function () {
            const { vpusd, owner, user1, user2 } = await loadFixture(deployVPUSDFixture);

            const MINTER_ROLE = await vpusd.MINTER_ROLE();
            const COMPLIANCE_ROLE = await vpusd.COMPLIANCE_ROLE();
            await vpusd.grantRole(MINTER_ROLE, owner.address);
            await vpusd.grantRole(COMPLIANCE_ROLE, owner.address);

            await vpusd.mint(user1.address, ethers.parseEther("1000"));
            await vpusd.freezeAccount(user1.address, "Test");

            await expect(
                vpusd.connect(user1).transfer(user2.address, ethers.parseEther("100"))
            ).to.be.revertedWith("Sender frozen");
        });
    });

    describe("Scheduled Payments", function () {
        it("Should create scheduled payment", async function () {
            const { vpusd, owner, user1, user2 } = await loadFixture(deployVPUSDFixture);

            const MINTER_ROLE = await vpusd.MINTER_ROLE();
            await vpusd.grantRole(MINTER_ROLE, owner.address);
            await vpusd.mint(user1.address, ethers.parseEther("1000"));

            const futureTime = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

            await expect(
                vpusd.connect(user1).scheduledPayment(
                    user2.address,
                    ethers.parseEther("100"),
                    futureTime
                )
            ).to.emit(vpusd, "ScheduledPayment");
        });
    });

    describe("Fee Management", function () {
        it("Should allow admin to update fee collector", async function () {
            const { vpusd, owner, user1 } = await loadFixture(deployVPUSDFixture);

            await vpusd.setFeeCollector(user1.address);
            expect(await vpusd.feeCollector()).to.equal(user1.address);
        });

        it("Should allow admin to update base payment fee", async function () {
            const { vpusd, owner } = await loadFixture(deployVPUSDFixture);

            await vpusd.setBasePaymentFee(20); // 0.2%
            expect(await vpusd.basePaymentFeeBps()).to.equal(20);
        });

        it("Should not allow fee above maximum", async function () {
            const { vpusd, owner } = await loadFixture(deployVPUSDFixture);

            await expect(
                vpusd.setBasePaymentFee(200) // 2% > 1% max
            ).to.be.revertedWith("Fee too high");
        });
    });

    describe("Pausable", function () {
        it("Should allow admin to pause", async function () {
            const { vpusd, owner } = await loadFixture(deployVPUSDFixture);

            await vpusd.pause();
            expect(await vpusd.paused()).to.be.true;
        });

        it("Should prevent operations when paused", async function () {
            const { vpusd, owner, user1, user2 } = await loadFixture(deployVPUSDFixture);

            const MINTER_ROLE = await vpusd.MINTER_ROLE();
            await vpusd.grantRole(MINTER_ROLE, owner.address);
            await vpusd.mint(user1.address, ethers.parseEther("1000"));

            await vpusd.pause();

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
            ).to.be.reverted;
        });
    });
});
