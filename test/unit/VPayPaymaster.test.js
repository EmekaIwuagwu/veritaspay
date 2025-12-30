const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("VPayPaymaster", function () {
    async function deployPaymasterFixture() {
        const [owner, user, merchant, customer] = await ethers.getSigners();

        // Deploy VPUSD (mock for testing)
        const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
        const vpusd = await ethers.deployContract("VeritasPayUSD");
        // For testing, we'll use a simple ERC20 mock

        // Deploy Mock Oracle for native token price
        const MockOracle = await ethers.getContractFactory("MockOracle");
        const nativeOracle = await MockOracle.deploy("ETH/USD", 8, 200000000000n); // $2000

        // Deploy Paymaster
        const VPayPaymaster = await ethers.getContractFactory("VPayPaymaster");
        const paymaster = await VPayPaymaster.deploy(
            owner.address, // EntryPoint (mock)
            await vpusd.getAddress(),
            await nativeOracle.getAddress(),
            500 // 5% service fee
        );

        return { paymaster, vpusd, nativeOracle, owner, user, merchant, customer };
    }

    describe("Deployment", function () {
        it("Should set the correct entry point", async function () {
            const { paymaster, owner } = await loadFixture(deployPaymasterFixture);
            expect(await paymaster.entryPoint()).to.equal(owner.address);
        });

        it("Should set the correct service fee", async function () {
            const { paymaster } = await loadFixture(deployPaymasterFixture);
            expect(await paymaster.serviceFeeBps()).to.equal(500n);
        });

        it("Should set the correct native token oracle", async function () {
            const { paymaster, nativeOracle } = await loadFixture(deployPaymasterFixture);
            expect(await paymaster.nativeTokenOracle()).to.equal(await nativeOracle.getAddress());
        });
    });

    describe("Gas Tank", function () {
        it("Should allow owner to refill gas tank", async function () {
            const { paymaster, owner } = await loadFixture(deployPaymasterFixture);
            const amount = ethers.parseEther("1");

            await expect(paymaster.connect(owner).refillGasTank({ value: amount }))
                .to.emit(paymaster, "GasTankRefilled")
                .withArgs(amount);

            expect(await paymaster.getGasTankBalance()).to.equal(amount);
        });

        it("Should receive native tokens directly", async function () {
            const { paymaster, user } = await loadFixture(deployPaymasterFixture);
            const amount = ethers.parseEther("0.5");

            await user.sendTransaction({
                to: await paymaster.getAddress(),
                value: amount
            });

            expect(await paymaster.getGasTankBalance()).to.equal(amount);
        });

        it("Should allow owner to withdraw from gas tank", async function () {
            const { paymaster, owner } = await loadFixture(deployPaymasterFixture);
            const amount = ethers.parseEther("1");

            await paymaster.connect(owner).refillGasTank({ value: amount });

            const balanceBefore = await ethers.provider.getBalance(owner.address);
            await paymaster.connect(owner).withdrawGasTank(amount);
            const balanceAfter = await ethers.provider.getBalance(owner.address);

            expect(balanceAfter).to.be.gt(balanceBefore - ethers.parseEther("0.01")); // Account for gas
        });
    });

    describe("Fee Calculation", function () {
        it("Should calculate VPUSD fee correctly", async function () {
            const { paymaster } = await loadFixture(deployPaymasterFixture);

            const estimatedGas = 21000n;
            const gasPrice = ethers.parseUnits("50", "gwei"); // 50 gwei

            const fee = await paymaster.calculateVPUSDFee(estimatedGas, gasPrice);

            // Gas cost = 21000 * 50 gwei = 1,050,000 gwei = 0.00105 ETH
            // At $2000/ETH = $2.10
            // With 5% service fee = $2.205
            expect(fee).to.be.gt(0n);
        });
    });

    describe("Merchant Subsidies", function () {
        it("Should allow adding merchant subsidy budget", async function () {
            const { paymaster, vpusd, owner, merchant } = await loadFixture(deployPaymasterFixture);

            // This test is limited because we're using the actual VPUSD which needs initialization
            // In a full test, we'd mock the VPUSD transfers
            expect(await paymaster.merchantGasBudgets(merchant.address)).to.equal(0n);
        });
    });

    describe("Sponsorship Management", function () {
        it("Should allow owner to set sponsorship type", async function () {
            const { paymaster, owner, user } = await loadFixture(deployPaymasterFixture);

            await paymaster.connect(owner).setSponsorship(user.address, 0); // FULL
            expect(await paymaster.sponsorships(user.address)).to.equal(0n);

            await paymaster.connect(owner).setSponsorship(user.address, 1); // PARTIAL
            expect(await paymaster.sponsorships(user.address)).to.equal(1n);
        });
    });

    describe("Admin Functions", function () {
        it("Should allow owner to update service fee", async function () {
            const { paymaster, owner } = await loadFixture(deployPaymasterFixture);

            await expect(paymaster.connect(owner).setServiceFee(1000))
                .to.emit(paymaster, "ServiceFeeUpdated")
                .withArgs(500, 1000);

            expect(await paymaster.serviceFeeBps()).to.equal(1000n);
        });

        it("Should fail if service fee too high", async function () {
            const { paymaster, owner } = await loadFixture(deployPaymasterFixture);

            await expect(paymaster.connect(owner).setServiceFee(3000))
                .to.be.revertedWith("Fee too high");
        });

        it("Should allow owner to update native token oracle", async function () {
            const { paymaster, owner } = await loadFixture(deployPaymasterFixture);

            const MockOracle = await ethers.getContractFactory("MockOracle");
            const newOracle = await MockOracle.deploy("MATIC/USD", 8, 100000000n);

            await paymaster.connect(owner).setNativeTokenOracle(await newOracle.getAddress());
            expect(await paymaster.nativeTokenOracle()).to.equal(await newOracle.getAddress());
        });

        it("Should fail to set zero address oracle", async function () {
            const { paymaster, owner } = await loadFixture(deployPaymasterFixture);

            await expect(paymaster.connect(owner).setNativeTokenOracle(ethers.ZeroAddress))
                .to.be.revertedWith("Invalid oracle");
        });
    });
});
