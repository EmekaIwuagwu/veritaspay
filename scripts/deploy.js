const { ethers, upgrades } = require("hardhat");

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with account:", deployer.address);

    // 1. Deploy VeritasPayUSD
    console.log("\n1. Deploying VeritasPayUSD...");
    const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
    const vpusd = await upgrades.deployProxy(
        VeritasPayUSD,
        [deployer.address, deployer.address, 10], // admin, feeCollector, 0.1% base fee
        { initializer: "initialize", kind: "uups" }
    );
    await vpusd.waitForDeployment();
    console.log("VeritasPayUSD deployed to:", await vpusd.getAddress());

    // 2. Deploy HybridVault
    console.log("\n2. Deploying HybridVault...");
    const HybridVault = await ethers.getContractFactory("HybridVault");
    const vault = await upgrades.deployProxy(
        HybridVault,
        [deployer.address, await vpusd.getAddress(), 15000, 17500], // admin, vpusd, 150% min, 175% target
        { initializer: "initialize", kind: "uups" }
    );
    await vault.waitForDeployment();
    console.log("HybridVault deployed to:", await vault.getAddress());

    // 3. Deploy VPayProcessor
    console.log("\n3. Deploying VPayProcessor...");
    const VPayProcessor = await ethers.getContractFactory("VPayProcessor");
    const processor = await upgrades.deployProxy(
        VPayProcessor,
        [deployer.address, await vpusd.getAddress(), deployer.address, 30], // admin, vpusd, feeCollector, 0.3% fee
        { initializer: "initialize", kind: "uups" }
    );
    await processor.waitForDeployment();
    console.log("VPayProcessor deployed to:", await processor.getAddress());

    // 4. Deploy VPayCompliance
    console.log("\n4. Deploying VPayCompliance...");
    const VPayCompliance = await ethers.getContractFactory("VPayCompliance");
    const compliance = await upgrades.deployProxy(
        VPayCompliance,
        [deployer.address, ethers.parseUnits("10000", 18)], // admin, $10k large tx threshold
        { initializer: "initialize", kind: "uups" }
    );
    await compliance.waitForDeployment();
    console.log("VPayCompliance deployed to:", await compliance.getAddress());

    // 5. Deploy VPayBridgeHub
    console.log("\n5. Deploying VPayBridgeHub...");
    const VPayBridgeHub = await ethers.getContractFactory("VPayBridgeHub");
    const bridge = await upgrades.deployProxy(
        VPayBridgeHub,
        [deployer.address, await vpusd.getAddress(), 5, ethers.parseUnits("100000", 18)], // admin, vpusd, 0.05% fee, $100k daily limit
        { initializer: "initialize", kind: "uups" }
    );
    await bridge.waitForDeployment();
    console.log("VPayBridgeHub deployed to:", await bridge.getAddress());

    // 6. Deploy VPayTreasury
    console.log("\n6. Deploying VPayTreasury...");
    const VPayTreasury = await ethers.getContractFactory("VPayTreasury");
    const treasury = await upgrades.deployProxy(
        VPayTreasury,
        [deployer.address, await vpusd.getAddress()],
        { initializer: "initialize", kind: "uups" }
    );
    await treasury.waitForDeployment();
    console.log("VPayTreasury deployed to:", await treasury.getAddress());

    // 7. Deploy VPayGovernance
    console.log("\n7. Deploying VPayGovernance...");
    const VPayGovernance = await ethers.getContractFactory("VPayGovernance");
    const governance = await upgrades.deployProxy(
        VPayGovernance,
        [deployer.address, [deployer.address], 1], // admin, signers, 1 required sig
        { initializer: "initialize", kind: "uups" }
    );
    await governance.waitForDeployment();
    console.log("VPayGovernance deployed to:", await governance.getAddress());

    // 8. Setup Roles
    console.log("\n8. Setting up roles...");

    // Grant MINTER_ROLE to HybridVault and BridgeHub
    const MINTER_ROLE = await vpusd.MINTER_ROLE();
    await vpusd.grantRole(MINTER_ROLE, await vault.getAddress());
    await vpusd.grantRole(MINTER_ROLE, await bridge.getAddress());
    console.log("Granted MINTER_ROLE to HybridVault and BridgeHub");

    // Set compliance oracle on processor
    await processor.setComplianceOracle(await compliance.getAddress());
    console.log("Set compliance oracle on VPayProcessor");

    // Summary
    console.log("\n========== DEPLOYMENT SUMMARY ==========");
    console.log("VeritasPayUSD:", await vpusd.getAddress());
    console.log("HybridVault:", await vault.getAddress());
    console.log("VPayProcessor:", await processor.getAddress());
    console.log("VPayCompliance:", await compliance.getAddress());
    console.log("VPayBridgeHub:", await bridge.getAddress());
    console.log("VPayTreasury:", await treasury.getAddress());
    console.log("VPayGovernance:", await governance.getAddress());
    console.log("=========================================\n");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
