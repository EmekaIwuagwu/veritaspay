const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("VPayGovernance", function () {
    async function deployGovernanceFixture() {
        const [owner, signer1, signer2, signer3, user] = await ethers.getSigners();

        // Deploy Governance
        const VPayGovernance = await ethers.getContractFactory("VPayGovernance");
        const governance = await upgrades.deployProxy(
            VPayGovernance,
            [owner.address, [owner.address, signer1.address, signer2.address], 2], // 2 of 3 multisig
            { initializer: "initialize", kind: "uups" }
        );

        // Deploy a pausable contract for testing emergency pause
        const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
        const vpusd = await upgrades.deployProxy(
            VeritasPayUSD,
            [owner.address, owner.address, 10],
            { initializer: "initialize", kind: "uups" }
        );

        return { governance, vpusd, owner, signer1, signer2, signer3, user };
    }

    describe("Deployment", function () {
        it("Should set the correct signers", async function () {
            const { governance, owner, signer1, signer2 } = await loadFixture(deployGovernanceFixture);
            expect(await governance.isValidSigner(owner.address)).to.be.true;
            expect(await governance.isValidSigner(signer1.address)).to.be.true;
            expect(await governance.isValidSigner(signer2.address)).to.be.true;
        });

        it("Should set the required signatures", async function () {
            const { governance } = await loadFixture(deployGovernanceFixture);
            expect(await governance.requiredSignatures()).to.equal(2n);
        });

        it("Should set total signers count", async function () {
            const { governance } = await loadFixture(deployGovernanceFixture);
            expect(await governance.totalSigners()).to.equal(3n);
        });
    });

    describe("Signer Management", function () {
        it("Should allow admin to add a signer", async function () {
            const { governance, owner, signer3 } = await loadFixture(deployGovernanceFixture);

            await governance.connect(owner).addSigner(signer3.address);
            expect(await governance.isValidSigner(signer3.address)).to.be.true;
            expect(await governance.totalSigners()).to.equal(4n);
        });

        it("Should fail to add existing signer", async function () {
            const { governance, owner, signer1 } = await loadFixture(deployGovernanceFixture);

            await expect(governance.connect(owner).addSigner(signer1.address))
                .to.be.revertedWith("Already signer");
        });

        it("Should allow admin to remove a signer", async function () {
            const { governance, owner, signer2 } = await loadFixture(deployGovernanceFixture);

            await governance.connect(owner).removeSigner(signer2.address);
            expect(await governance.isValidSigner(signer2.address)).to.be.false;
            expect(await governance.totalSigners()).to.equal(2n);
        });
    });

    describe("Emergency Actions", function () {
        it("Should require multi-sig confirmation for emergency pause", async function () {
            const { governance, vpusd, owner, signer1 } = await loadFixture(deployGovernanceFixture);
            const vpusdAddress = await vpusd.getAddress();

            // First signer confirms
            await governance.connect(owner).emergencyPause(vpusdAddress);

            // Contract should not be paused yet (need 2 confirmations)
            expect(await vpusd.paused()).to.be.false;
        });

        it("Should execute pause after reaching quorum", async function () {
            const { governance, vpusd, owner, signer1 } = await loadFixture(deployGovernanceFixture);
            const vpusdAddress = await vpusd.getAddress();

            // Grant governance the pauser role
            await vpusd.connect(owner).grantRole(await vpusd.DEFAULT_ADMIN_ROLE(), await governance.getAddress());

            // First signer confirms
            await governance.connect(owner).emergencyPause(vpusdAddress);

            // Second signer confirms - should execute
            await expect(governance.connect(signer1).emergencyPause(vpusdAddress))
                .to.emit(governance, "EmergencyActionExecuted");
        });

        it("Should reject non-signer from calling emergency pause", async function () {
            const { governance, vpusd, user } = await loadFixture(deployGovernanceFixture);

            await expect(governance.connect(user).emergencyPause(await vpusd.getAddress()))
                .to.be.revertedWith("Not a signer");
        });
    });

    describe("Proposals", function () {
        it("Should allow creating a proposal", async function () {
            const { governance, owner } = await loadFixture(deployGovernanceFixture);

            await expect(governance.connect(owner).propose(
                "Increase reserve ratio",
                0, // PARAMETER_CHANGE
                owner.address,
                "0x"
            )).to.emit(governance, "ProposalCreated");
        });

        it("Should allow voting on a proposal", async function () {
            const { governance, owner, signer1 } = await loadFixture(deployGovernanceFixture);

            await governance.connect(owner).propose(
                "Test proposal",
                0,
                owner.address,
                "0x"
            );

            await expect(governance.connect(signer1).castVote(1, true))
                .to.emit(governance, "VoteCast");
        });

        it("Should prevent double voting", async function () {
            const { governance, owner, signer1 } = await loadFixture(deployGovernanceFixture);

            await governance.connect(owner).propose(
                "Test proposal",
                0,
                owner.address,
                "0x"
            );

            await governance.connect(signer1).castVote(1, true);

            await expect(governance.connect(signer1).castVote(1, true))
                .to.be.revertedWith("Already voted");
        });
    });

    describe("Parameter Updates", function () {
        it("Should allow admin to update system parameter", async function () {
            const { governance, owner } = await loadFixture(deployGovernanceFixture);

            await governance.connect(owner).updateParameter("minReserveRatio", 16000);
            const params = await governance.systemParameters();
            expect(params.minReserveRatio).to.equal(16000n);
        });

        it("Should fail for invalid parameter name", async function () {
            const { governance, owner } = await loadFixture(deployGovernanceFixture);

            await expect(governance.connect(owner).updateParameter("invalidParam", 100))
                .to.be.revertedWith("Invalid parameter");
        });
    });
});
