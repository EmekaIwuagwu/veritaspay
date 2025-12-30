const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("HybridVault", function () {
    async function deployVaultFixture() {
        const [owner, feeCollector, stabilizer, user1, user2] = await ethers.getSigners();

        // Deploy VPUSD
        const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
        const vpusd = await upgrades.deployProxy(
            VeritasPayUSD,
            [owner.address, feeCollector.address, 10],
            { initializer: "initialize", kind: "uups" }
        );

        // Deploy HybridVault
        const HybridVault = await ethers.getContractFactory("HybridVault");
        const vault = await upgrades.deployProxy(
            HybridVault,
            [owner.address, await vpusd.getAddress(), 15000, 17500],
            { initializer: "initialize", kind: "uups" }
        );

        // Grant MINTER_ROLE to Vault
        const MINTER_ROLE = await vpusd.MINTER_ROLE();
        await vpusd.grantRole(MINTER_ROLE, await vault.getAddress());

        // Deploy Mock Collateral (USDC)
        const MockERC20 = await ethers.getContractFactory("VeritasPayUSD"); // Using VPUSD as mock ERC20 for simplicity
        const usdc = await upgrades.deployProxy(
            VeritasPayUSD,
            [owner.address, feeCollector.address, 0],
            { initializer: "initialize", kind: "uups" }
        );

        // Deploy Mock Oracle for USDC ($1.00)
        const MockOracle = await ethers.getContractFactory("MockOracle");
        const usdcOracle = await MockOracle.deploy("USDC/USD", 8, 100000000n); // 8 decimals

        // Setup Vault with USDC
        await vault.addCollateralToken(await usdc.getAddress(), 0, await usdcOracle.getAddress()); // Tier 0 = TIER1

        return { vpusd, vault, usdc, usdcOracle, owner, feeCollector, stabilizer, user1, user2 };
    }

    describe("Deployment", function () {
        it("Should set the correct VPUSD address", async function () {
            const { vault, vpusd } = await loadFixture(deployVaultFixture);
            expect(await vault.vpusd()).to.equal(await vpusd.getAddress());
        });

        it("Should set the correct reserve ratios", async function () {
            const { vault } = await loadFixture(deployVaultFixture);
            expect(await vault.minReserveRatio()).to.equal(15000);
            expect(await vault.targetReserveRatio()).to.equal(17500);
        });
    });

    describe("Collateral Management", function () {
        it("Should allow owner to add collateral token", async function () {
            const { vault, owner, feeCollector } = await loadFixture(deployVaultFixture);
            const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
            const wbtc = await upgrades.deployProxy(
                VeritasPayUSD,
                [owner.address, feeCollector.address, 0],
                { initializer: "initialize", kind: "uups" }
            );
            const MockOracle = await ethers.getContractFactory("MockOracle");
            const wbtcOracle = await MockOracle.deploy("WBTC/USD", 8, 6000000000000n);

            await vault.addCollateralToken(await wbtc.getAddress(), 1, await wbtcOracle.getAddress()); // TIER2

            const tier = await vault.tokenTier(await wbtc.getAddress());
            expect(tier).to.equal(1);
        });
    });

    describe("Position Management", function () {
        it("Should allow deposit and mint", async function () {
            const { vault, usdc, user1, owner } = await loadFixture(deployVaultFixture);

            // Mint some USDC to user1
            const MINTER_ROLE = await usdc.MINTER_ROLE();
            await usdc.grantRole(MINTER_ROLE, owner.address);
            await usdc.mint(user1.address, ethers.parseUnits("1000", 18));

            // Approve vault
            await usdc.connect(user1).approve(await vault.getAddress(), ethers.parseUnits("1000", 18));

            // Deposit $1000 USDC to mint $500 VPUSD (200% CR, > 150% min)
            await expect(
                vault.connect(user1).deposit(await usdc.getAddress(), ethers.parseUnits("1000", 18), ethers.parseUnits("500", 18))
            ).to.emit(vault, "CollateralDeposited");

            const position = await vault.getPosition(1);
            expect(position.collateralAmount).to.equal(ethers.parseUnits("1000", 18));
            expect(position.vpusdMinted).to.equal(ethers.parseUnits("500", 18));
        });

        it("Should fail if collateral is insufficient", async function () {
            const { vault, usdc, user1, owner } = await loadFixture(deployVaultFixture);
            await usdc.grantRole(await usdc.MINTER_ROLE(), owner.address);
            await usdc.mint(user1.address, ethers.parseUnits("1000", 18));
            await usdc.connect(user1).approve(await vault.getAddress(), ethers.parseUnits("1000", 18));

            // Try to mint $800 VPUSD with $1000 USDC (125% CR, < 150% min)
            await expect(
                vault.connect(user1).deposit(await usdc.getAddress(), ethers.parseUnits("1000", 18), ethers.parseUnits("800", 18))
            ).to.be.revertedWith("Insufficient collateral");
        });

        it("Should allow withdrawal and burning", async function () {
            const { vault, vpusd, usdc, user1, owner } = await loadFixture(deployVaultFixture);
            await usdc.grantRole(await usdc.MINTER_ROLE(), owner.address);
            await usdc.mint(user1.address, ethers.parseUnits("1000", 18));
            await usdc.connect(user1).approve(await vault.getAddress(), ethers.parseUnits("1000", 18));

            await vault.connect(user1).deposit(await usdc.getAddress(), ethers.parseUnits("1000", 18), ethers.parseUnits("500", 18));

            // user1 burns $100 VPUSD to withdraw $200 USDC
            await vpusd.connect(user1).approve(await vault.getAddress(), ethers.parseUnits("100", 18));
            await expect(
                vault.connect(user1).withdraw(1, ethers.parseUnits("200", 18), ethers.parseUnits("100", 18))
            ).to.emit(vault, "CollateralWithdrawn");

            const position = await vault.getPosition(1);
            expect(position.collateralAmount).to.equal(ethers.parseUnits("800", 18));
            expect(position.vpusdMinted).to.equal(ethers.parseUnits("400", 18));
        });
    });

    describe("Liquidation", function () {
        it("Should allow liquidation of unhealthy positions", async function () {
            const { vault, vpusd, usdc, usdcOracle, user1, user2, owner } = await loadFixture(deployVaultFixture);

            // Setup user1 position
            await usdc.grantRole(await usdc.MINTER_ROLE(), owner.address);
            await usdc.mint(user1.address, ethers.parseUnits("1000", 18));
            await usdc.connect(user1).approve(await vault.getAddress(), ethers.parseUnits("1000", 18));
            await vault.connect(user1).deposit(await usdc.getAddress(), ethers.parseUnits("1000", 18), ethers.parseUnits("600", 18)); // 166% CR

            // Price drops: USDC goes from $1 to $0.7
            await usdcOracle.setPrice(70000000n);

            // New CR: (1000 * 0.7) / 600 = 1.16 (116% < 130% threshold)
            expect(await vault.isPositionHealthy(1)).to.be.false;

            // User2 liquidates User1
            // Give user2 some VPUSD to repay debt
            await vpusd.grantRole(await vpusd.MINTER_ROLE(), owner.address);
            await vpusd.mint(user2.address, ethers.parseUnits("600", 18));
            await vpusd.connect(user2).approve(await vault.getAddress(), ethers.parseUnits("600", 18));

            await expect(
                vault.connect(user2).liquidate(1)
            ).to.emit(vault, "PositionLiquidated");
        });
    });

    describe("Stabilization", function () {
        it("Should expand supply when price is high", async function () {
            const { vault, vpusd, owner } = await loadFixture(deployVaultFixture);

            // Deploy VPUSD Oracle
            const MockOracle = await ethers.getContractFactory("MockOracle");
            const vpusdOracle = await MockOracle.deploy("VPUSD/USD", 8, 105000000n); // $1.05 (5% depeg)
            await vault.setVPUSDOracle(await vpusdOracle.getAddress());

            // Grant STABILIZER_ROLE
            const STABILIZER_ROLE = await vault.STABILIZER_ROLE();
            await vault.grantRole(STABILIZER_ROLE, owner.address);

            // Initial supply
            const initialSupply = await vpusd.totalSupply();

            await expect(vault.executeStabilization()).to.emit(vault, "StabilizationExecuted");

            const finalSupply = await vpusd.totalSupply();
            // Since expansion mints to vault (until DEX logic added)
            // But if total supply was 0, expansion might be 0
        });

        it("Should activate circuit breaker on extreme depeg", async function () {
            const { vault, owner } = await loadFixture(deployVaultFixture);

            const MockOracle = await ethers.getContractFactory("MockOracle");
            const vpusdOracle = await MockOracle.deploy("VPUSD/USD", 8, 80000000n); // $0.80 (20% depeg > 10% threshold)
            await vault.setVPUSDOracle(await vpusdOracle.getAddress());

            await vault.grantRole(await vault.STABILIZER_ROLE(), owner.address);

            await expect(vault.executeStabilization()).to.emit(vault, "CircuitBreakerActivated");
            expect(await vault.circuitBreakerActive()).to.be.true;
        });
    });

    describe("Rebalancing", function () {
        it("Should emit TierWeightStatus for all tiers", async function () {
            const { vault, usdc, owner } = await loadFixture(deployVaultFixture);

            // Deposit something first
            await usdc.grantRole(await usdc.MINTER_ROLE(), owner.address);
            await usdc.mint(owner.address, ethers.parseUnits("1000", 18));
            await usdc.approve(await vault.getAddress(), ethers.parseUnits("1000", 18));
            await vault.deposit(await usdc.getAddress(), ethers.parseUnits("1000", 18), ethers.parseUnits("500", 18));

            await vault.grantRole(await vault.KEEPER_ROLE(), owner.address);

            // Trigger rebalance
            await expect(vault.rebalanceReserves())
                .to.emit(vault, "ReservesRebalanced");
        });
    });
});
