const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("VPayTreasury", function () {
    async function deployTreasuryFixture() {
        const [owner, staker1, staker2, devWallet, insuranceWallet] = await ethers.getSigners();

        // Deploy VPUSD
        const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
        const vpusd = await upgrades.deployProxy(
            VeritasPayUSD,
            [owner.address, owner.address, 10],
            { initializer: "initialize", kind: "uups" }
        );

        // Deploy Treasury
        const VPayTreasury = await ethers.getContractFactory("VPayTreasury");
        const treasury = await upgrades.deployProxy(
            VPayTreasury,
            [owner.address, await vpusd.getAddress()],
            { initializer: "initialize", kind: "uups" }
        );

        // Mint VPUSD for testing
        await vpusd.grantRole(await vpusd.MINTER_ROLE(), owner.address);
        await vpusd.mint(staker1.address, ethers.parseUnits("10000", 18));
        await vpusd.mint(staker2.address, ethers.parseUnits("10000", 18));
        await vpusd.mint(owner.address, ethers.parseUnits("100000", 18));

        return { treasury, vpusd, owner, staker1, staker2, devWallet, insuranceWallet };
    }

    describe("Deployment", function () {
        it("Should set the correct VPUSD address", async function () {
            const { treasury, vpusd } = await loadFixture(deployTreasuryFixture);
            expect(await treasury.vpusd()).to.equal(await vpusd.getAddress());
        });

        it("Should set default allocation percentages", async function () {
            const { treasury } = await loadFixture(deployTreasuryFixture);
            expect(await treasury.allocationBps(0)).to.equal(4000n); // STAKERS 40%
            expect(await treasury.allocationBps(1)).to.equal(2000n); // DEVELOPMENT 20%
            expect(await treasury.allocationBps(2)).to.equal(2000n); // INSURANCE 20%
        });

        it("Should set default APY rates", async function () {
            const { treasury } = await loadFixture(deployTreasuryFixture);
            expect(await treasury.getAPY(30 * 24 * 60 * 60)).to.equal(500n); // 5% for 30 days
            expect(await treasury.getAPY(365 * 24 * 60 * 60)).to.equal(2500n); // 25% for 1 year
        });
    });

    describe("Staking", function () {
        it("Should allow user to stake VPUSD", async function () {
            const { treasury, vpusd, staker1 } = await loadFixture(deployTreasuryFixture);
            const stakeAmount = ethers.parseUnits("1000", 18);
            const lockPeriod = 30 * 24 * 60 * 60; // 30 days

            await vpusd.connect(staker1).approve(await treasury.getAddress(), stakeAmount);

            await expect(treasury.connect(staker1).stakeVPUSD(stakeAmount, lockPeriod))
                .to.emit(treasury, "Staked")
                .withArgs(staker1.address, 0, stakeAmount, lockPeriod);

            expect(await treasury.totalStaked()).to.equal(stakeAmount);
        });

        it("Should fail for invalid lock period", async function () {
            const { treasury, vpusd, staker1 } = await loadFixture(deployTreasuryFixture);
            const stakeAmount = ethers.parseUnits("1000", 18);

            await vpusd.connect(staker1).approve(await treasury.getAddress(), stakeAmount);

            await expect(treasury.connect(staker1).stakeVPUSD(stakeAmount, 1000))
                .to.be.revertedWith("Invalid lock period");
        });

        it("Should create multiple staking positions for same user", async function () {
            const { treasury, vpusd, staker1 } = await loadFixture(deployTreasuryFixture);
            const stakeAmount = ethers.parseUnits("500", 18);
            const lockPeriod = 30 * 24 * 60 * 60;

            await vpusd.connect(staker1).approve(await treasury.getAddress(), stakeAmount * 2n);

            await treasury.connect(staker1).stakeVPUSD(stakeAmount, lockPeriod);
            await treasury.connect(staker1).stakeVPUSD(stakeAmount, lockPeriod);

            expect(await treasury.userStakeCount(staker1.address)).to.equal(2n);
            expect(await treasury.totalStaked()).to.equal(stakeAmount * 2n);
        });
    });

    describe("Unstaking", function () {
        it("Should allow unstaking after lock period", async function () {
            const { treasury, vpusd, staker1, owner } = await loadFixture(deployTreasuryFixture);
            const stakeAmount = ethers.parseUnits("1000", 18);
            const lockPeriod = 30 * 24 * 60 * 60;

            await vpusd.connect(staker1).approve(await treasury.getAddress(), stakeAmount);
            await treasury.connect(staker1).stakeVPUSD(stakeAmount, lockPeriod);

            // Mint extra tokens to treasury for rewards
            await vpusd.mint(await treasury.getAddress(), ethers.parseUnits("1000", 18));

            // Fast forward past lock period
            await time.increase(lockPeriod + 1);

            const balanceBefore = await vpusd.balanceOf(staker1.address);
            await treasury.connect(staker1).unstake(0);
            const balanceAfter = await vpusd.balanceOf(staker1.address);

            expect(balanceAfter).to.be.gt(balanceBefore);
            expect(await treasury.totalStaked()).to.equal(0n);
        });

        it("Should fail if still locked", async function () {
            const { treasury, vpusd, staker1 } = await loadFixture(deployTreasuryFixture);
            const stakeAmount = ethers.parseUnits("1000", 18);
            const lockPeriod = 30 * 24 * 60 * 60;

            await vpusd.connect(staker1).approve(await treasury.getAddress(), stakeAmount);
            await treasury.connect(staker1).stakeVPUSD(stakeAmount, lockPeriod);

            await expect(treasury.connect(staker1).unstake(0))
                .to.be.revertedWith("Still locked");
        });
    });

    describe("Revenue Management", function () {
        it("Should allow admin to set allocation wallet", async function () {
            const { treasury, owner, devWallet } = await loadFixture(deployTreasuryFixture);

            await treasury.connect(owner).setAllocationWallet(1, devWallet.address); // DEVELOPMENT
            expect(await treasury.allocationWallets(1)).to.equal(devWallet.address);
        });

        it("Should allow admin to update APY", async function () {
            const { treasury, owner } = await loadFixture(deployTreasuryFixture);
            const lockPeriod = 30 * 24 * 60 * 60;

            await treasury.connect(owner).setAPY(lockPeriod, 800); // 8%
            expect(await treasury.getAPY(lockPeriod)).to.equal(800n);
        });

        it("Should record payment fees", async function () {
            const { treasury, owner } = await loadFixture(deployTreasuryFixture);

            await treasury.connect(owner).recordPaymentFees(ethers.parseUnits("100", 18));
            const revenue = await treasury.revenueSource();
            expect(revenue.paymentFees).to.equal(ethers.parseUnits("100", 18));
        });

        it("Should record bridge fees", async function () {
            const { treasury, owner } = await loadFixture(deployTreasuryFixture);

            await treasury.connect(owner).recordBridgeFees(ethers.parseUnits("50", 18));
            const revenue = await treasury.revenueSource();
            expect(revenue.bridgeFees).to.equal(ethers.parseUnits("50", 18));
        });
    });
});
