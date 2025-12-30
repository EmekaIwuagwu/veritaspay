const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("VPayBridgeHub", function () {
    async function deployBridgeFixture() {
        const [owner, operator, user1, user2] = await ethers.getSigners();

        // Deploy VPUSD
        const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
        const vpusd = await upgrades.deployProxy(
            VeritasPayUSD,
            [owner.address, owner.address, 10],
            { initializer: "initialize", kind: "uups" }
        );

        // Deploy VPayBridgeHub
        const VPayBridgeHub = await ethers.getContractFactory("VPayBridgeHub");
        const bridge = await upgrades.deployProxy(
            VPayBridgeHub,
            [owner.address, await vpusd.getAddress(), 5, ethers.parseUnits("10000", 18)], // 0.05% fee, $10k limit
            { initializer: "initialize", kind: "uups" }
        );

        // Grant roles
        const BRIDGE_OPERATOR_ROLE = await bridge.BRIDGE_OPERATOR_ROLE();
        await bridge.grantRole(BRIDGE_OPERATOR_ROLE, operator.address);

        const MINTER_ROLE = await vpusd.MINTER_ROLE();
        await vpusd.grantRole(MINTER_ROLE, await bridge.getAddress());

        return { vpusd, bridge, owner, operator, user1, user2 };
    }

    describe("Bridge Operations", function () {
        it("Should allow bridging payment", async function () {
            const { vpusd, bridge, user1, owner } = await loadFixture(deployBridgeFixture);

            // Mint VPUSD to user1
            await vpusd.grantRole(await vpusd.MINTER_ROLE(), owner.address);
            await vpusd.mint(user1.address, ethers.parseUnits("1000", 18));

            await expect(
                bridge.connect(user1).bridgePayment(
                    42161, // Arbitrum
                    user1.address,
                    ethers.parseUnits("100", 18),
                    0, // LAYERZERO
                    "0x"
                )
            ).to.emit(bridge, "PaymentBridged");

            expect(await vpusd.balanceOf(user1.address)).to.equal(ethers.parseUnits("900", 18));
        });

        it("Should fail if rate limit exceeded", async function () {
            const { vpusd, bridge, user1, owner } = await loadFixture(deployBridgeFixture);

            await vpusd.grantRole(await vpusd.MINTER_ROLE(), owner.address);
            // $20,000 VPUSD (exceeds $10,000 daily limit)
            await vpusd.mint(user1.address, ethers.parseUnits("20000", 18));

            await expect(
                bridge.connect(user1).bridgePayment(
                    42161,
                    user1.address,
                    ethers.parseUnits("15000", 18),
                    0,
                    "0x"
                )
            ).to.be.revertedWith("Rate limit exceeded");
        });

        it("Should allow operator to complete bridge on destination chain", async function () {
            const { vpusd, bridge, operator, user2 } = await loadFixture(deployBridgeFixture);

            const bridgeId = ethers.id("BRIDGE-123");
            const amount = ethers.parseUnits("100", 18);

            await expect(
                bridge.connect(operator).receiveBridgedPayment(bridgeId, user2.address, amount)
            ).to.emit(vpusd, "Transfer"); // Minting triggers transfer event

            expect(await vpusd.balanceOf(user2.address)).to.equal(amount);
        });
    });

    describe("Route Management", function () {
        it("Should allow admin to add route", async function () {
            const { bridge, owner } = await loadFixture(deployBridgeFixture);

            await expect(
                bridge.addRoute(1, 42161, 0, 300, 100)
            ).to.emit(bridge, "RouteUpdated");
        });
    });
});
