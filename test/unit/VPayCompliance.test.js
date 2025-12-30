const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("VPayCompliance", function () {
    async function deployComplianceFixture() {
        const [owner, officer, user1, user2, sanctionedUser] = await ethers.getSigners();

        // Deploy Compliance
        const VPayCompliance = await ethers.getContractFactory("VPayCompliance");
        const compliance = await upgrades.deployProxy(
            VPayCompliance,
            [owner.address, ethers.parseUnits("10000", 18)], // $10k large tx threshold
            { initializer: "initialize", kind: "uups" }
        );

        // Grant compliance officer role
        await compliance.grantRole(await compliance.COMPLIANCE_OFFICER_ROLE(), officer.address);

        return { compliance, owner, officer, user1, user2, sanctionedUser };
    }

    describe("Deployment", function () {
        it("Should set the correct large transaction threshold", async function () {
            const { compliance } = await loadFixture(deployComplianceFixture);
            expect(await compliance.largeTransactionThreshold()).to.equal(ethers.parseUnits("10000", 18));
        });

        it("Should grant compliance officer role to admin", async function () {
            const { compliance, owner } = await loadFixture(deployComplianceFixture);
            expect(await compliance.hasRole(await compliance.COMPLIANCE_OFFICER_ROLE(), owner.address)).to.be.true;
        });
    });

    describe("User Verification", function () {
        it("Should allow officer to verify user", async function () {
            const { compliance, officer, user1 } = await loadFixture(deployComplianceFixture);

            await expect(compliance.connect(officer).verifyUser(user1.address))
                .to.emit(compliance, "UserVerified");

            expect(await compliance.isVerified(user1.address)).to.be.true;
        });

        it("Should set low risk score for verified users", async function () {
            const { compliance, officer, user1 } = await loadFixture(deployComplianceFixture);

            await compliance.connect(officer).verifyUser(user1.address);
            expect(await compliance.getRiskScore(user1.address)).to.equal(20n);
        });

        it("Should allow batch verification", async function () {
            const { compliance, officer, user1, user2 } = await loadFixture(deployComplianceFixture);

            await compliance.connect(officer).batchVerifyUsers([user1.address, user2.address]);

            expect(await compliance.isVerified(user1.address)).to.be.true;
            expect(await compliance.isVerified(user2.address)).to.be.true;
        });

        it("Should fail to verify sanctioned user", async function () {
            const { compliance, officer, sanctionedUser } = await loadFixture(deployComplianceFixture);

            await compliance.connect(officer).addToSanctionList(sanctionedUser.address, "OFAC list");

            await expect(compliance.connect(officer).verifyUser(sanctionedUser.address))
                .to.be.revertedWith("User is sanctioned");
        });
    });

    describe("Sanction List", function () {
        it("Should allow officer to add user to sanction list", async function () {
            const { compliance, officer, sanctionedUser } = await loadFixture(deployComplianceFixture);

            await expect(compliance.connect(officer).addToSanctionList(sanctionedUser.address, "Suspected fraud"))
                .to.emit(compliance, "AddressSanctioned")
                .withArgs(sanctionedUser.address, "Suspected fraud");

            expect(await compliance.isSanctioned(sanctionedUser.address)).to.be.true;
        });

        it("Should allow batch sanctioning", async function () {
            const { compliance, officer, user1, user2 } = await loadFixture(deployComplianceFixture);

            await compliance.connect(officer).batchAddToSanctionList(
                [user1.address, user2.address],
                "Bulk sanction"
            );

            expect(await compliance.isSanctioned(user1.address)).to.be.true;
            expect(await compliance.isSanctioned(user2.address)).to.be.true;
        });

        it("Should allow removing from sanction list", async function () {
            const { compliance, officer, sanctionedUser } = await loadFixture(deployComplianceFixture);

            await compliance.connect(officer).addToSanctionList(sanctionedUser.address, "Error");
            await expect(compliance.connect(officer).removeFromSanctionList(sanctionedUser.address))
                .to.emit(compliance, "AddressUnsanctioned");

            expect(await compliance.isSanctioned(sanctionedUser.address)).to.be.false;
        });
    });

    describe("Risk Analysis", function () {
        it("Should analyze transaction risk for verified users", async function () {
            const { compliance, officer, user1, user2 } = await loadFixture(deployComplianceFixture);

            await compliance.connect(officer).verifyUser(user1.address);
            await compliance.connect(officer).verifyUser(user2.address);

            const risk = await compliance.analyzeTransaction(
                user1.address,
                user2.address,
                ethers.parseUnits("1000", 18)
            );

            expect(risk.riskScore).to.be.lt(50); // Low risk
            expect(risk.requiresReview).to.be.false;
        });

        it("Should flag high-risk transactions with unverified users", async function () {
            const { compliance, user1, user2 } = await loadFixture(deployComplianceFixture);

            const risk = await compliance.analyzeTransaction(
                user1.address,
                user2.address,
                ethers.parseUnits("1000", 18)
            );

            expect(risk.riskScore).to.be.gte(40); // Higher risk for unverified
        });

        it("Should flag transactions involving sanctioned addresses", async function () {
            const { compliance, officer, user1, sanctionedUser } = await loadFixture(deployComplianceFixture);

            await compliance.connect(officer).addToSanctionList(sanctionedUser.address, "Test");

            const risk = await compliance.analyzeTransaction(
                user1.address,
                sanctionedUser.address,
                ethers.parseUnits("100", 18)
            );

            expect(risk.riskScore).to.be.gte(50); // Very high risk
            expect(risk.requiresReview).to.be.true;
        });

        it("Should flag large transactions", async function () {
            const { compliance, officer, user1, user2 } = await loadFixture(deployComplianceFixture);

            await compliance.connect(officer).verifyUser(user1.address);
            await compliance.connect(officer).verifyUser(user2.address);

            const risk = await compliance.analyzeTransaction(
                user1.address,
                user2.address,
                ethers.parseUnits("15000", 18) // Above threshold
            );

            expect(risk.flags.length).to.be.gt(0);
        });
    });

    describe("Transaction Recording", function () {
        it("Should record transactions", async function () {
            const { compliance, user1, user2 } = await loadFixture(deployComplianceFixture);

            await compliance.recordTransaction(
                user1.address,
                user2.address,
                ethers.parseUnits("500", 18)
            );

            expect(await compliance.getTransactionHistoryCount()).to.equal(1n);
        });

        it("Should flag and emit event for high-risk transactions", async function () {
            const { compliance, officer, sanctionedUser, user2 } = await loadFixture(deployComplianceFixture);

            await compliance.connect(officer).addToSanctionList(sanctionedUser.address, "Test");

            await expect(compliance.recordTransaction(
                sanctionedUser.address,
                user2.address,
                ethers.parseUnits("500", 18)
            )).to.emit(compliance, "TransactionFlagged");
        });

        it("Should auto-adjust risk scores for large transactions", async function () {
            const { compliance, officer, user1, user2 } = await loadFixture(deployComplianceFixture);

            await compliance.connect(officer).verifyUser(user1.address);
            const initialScore = await compliance.getRiskScore(user1.address);

            await compliance.recordTransaction(
                user1.address,
                user2.address,
                ethers.parseUnits("15000", 18) // Large tx
            );

            const newScore = await compliance.getRiskScore(user1.address);
            expect(newScore).to.be.gt(initialScore);
        });
    });

    describe("Admin Functions", function () {
        it("Should allow admin to update large transaction threshold", async function () {
            const { compliance, owner } = await loadFixture(deployComplianceFixture);

            await compliance.connect(owner).setLargeTransactionThreshold(ethers.parseUnits("50000", 18));
            expect(await compliance.largeTransactionThreshold()).to.equal(ethers.parseUnits("50000", 18));
        });

        it("Should allow officer to update user risk score", async function () {
            const { compliance, officer, user1 } = await loadFixture(deployComplianceFixture);

            await compliance.connect(officer).updateRiskScore(user1.address, 75);
            expect(await compliance.getRiskScore(user1.address)).to.equal(75n);
        });

        it("Should fail for invalid risk score", async function () {
            const { compliance, officer, user1 } = await loadFixture(deployComplianceFixture);

            await expect(compliance.connect(officer).updateRiskScore(user1.address, 150))
                .to.be.revertedWith("Invalid score");
        });
    });

    describe("Audit Reports", function () {
        it("Should generate audit report", async function () {
            const { compliance, user1, user2 } = await loadFixture(deployComplianceFixture);

            // Record some transactions
            await compliance.recordTransaction(user1.address, user2.address, ethers.parseUnits("100", 18));
            await compliance.recordTransaction(user2.address, user1.address, ethers.parseUnits("200", 18));

            const now = Math.floor(Date.now() / 1000);
            const report = await compliance.generateAuditReport(now - 3600, now + 3600);

            // Decode the report
            const decoded = ethers.AbiCoder.defaultAbiCoder().decode(
                ["uint256", "uint256", "uint256", "uint256", "uint256"],
                report
            );

            expect(decoded[0]).to.equal(2n); // Total transactions
            expect(decoded[2]).to.equal(ethers.parseUnits("300", 18)); // Total volume
        });
    });
});
