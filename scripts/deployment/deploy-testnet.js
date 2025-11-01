const hre = require("hardhat");
const { ethers, upgrades } = require("hardhat");

async function main() {
    console.log("\n🚀 ========================================");
    console.log("   VERITASPAY USD (VPUSD) - TESTNET DEPLOYMENT");
    console.log("   ==========================================\n");

    const [deployer] = await ethers.getSigners();
    console.log("📍 Deploying with account:", deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH\n");

    const network = await ethers.provider.getNetwork();
    console.log("🌐 Network:", network.name, "(Chain ID:", network.chainId, ")\n");

    // ========================================
    // CONFIGURATION
    // ========================================
    const ADMIN_ADDRESS = deployer.address;
    const FEE_COLLECTOR = deployer.address;
    const TREASURY_WALLET = deployer.address;

    const BASE_PAYMENT_FEE_BPS = 10; // 0.1%
    const MERCHANT_FEE_BPS = 30; // 0.3%
    const BRIDGE_FEE_BPS = 5; // 0.05%
    const MIN_RESERVE_RATIO = 15000; // 150%
    const TARGET_RESERVE_RATIO = 17500; // 175%
    const LARGE_TX_THRESHOLD = ethers.parseEther("10000"); // $10,000
    const DAILY_RATE_LIMIT = ethers.parseEther("100000"); // $100,000

    console.log("⚙️  Configuration:");
    console.log("   Admin:", ADMIN_ADDRESS);
    console.log("   Fee Collector:", FEE_COLLECTOR);
    console.log("   Base Payment Fee:", BASE_PAYMENT_FEE_BPS, "bps");
    console.log("   Merchant Fee:", MERCHANT_FEE_BPS, "bps\n");

    // ========================================
    // 1. DEPLOY VPUSD TOKEN
    // ========================================
    console.log("📝 Step 1: Deploying VeritasPayUSD Token (VPUSD)...");
    const VeritasPayUSD = await ethers.getContractFactory("VeritasPayUSD");
    const vpusd = await upgrades.deployProxy(
        VeritasPayUSD,
        [ADMIN_ADDRESS, FEE_COLLECTOR, BASE_PAYMENT_FEE_BPS],
        { initializer: "initialize", kind: "uups" }
    );
    await vpusd.waitForDeployment();
    const vpusdAddress = await vpusd.getAddress();
    console.log("✅ VPUSD deployed at:", vpusdAddress, "\n");

    // ========================================
    // 2. DEPLOY HYBRID VAULT
    // ========================================
    console.log("📝 Step 2: Deploying HybridVault...");
    const HybridVault = await ethers.getContractFactory("HybridVault");
    const vault = await upgrades.deployProxy(
        HybridVault,
        [ADMIN_ADDRESS, vpusdAddress, MIN_RESERVE_RATIO, TARGET_RESERVE_RATIO],
        { initializer: "initialize", kind: "uups" }
    );
    await vault.waitForDeployment();
    const vaultAddress = await vault.getAddress();
    console.log("✅ HybridVault deployed at:", vaultAddress, "\n");

    // ========================================
    // 3. DEPLOY COMPLIANCE
    // ========================================
    console.log("📝 Step 3: Deploying VPayCompliance...");
    const VPayCompliance = await ethers.getContractFactory("VPayCompliance");
    const compliance = await upgrades.deployProxy(
        VPayCompliance,
        [ADMIN_ADDRESS, LARGE_TX_THRESHOLD],
        { initializer: "initialize", kind: "uups" }
    );
    await compliance.waitForDeployment();
    const complianceAddress = await compliance.getAddress();
    console.log("✅ VPayCompliance deployed at:", complianceAddress, "\n");

    // ========================================
    // 4. DEPLOY PAYMENT PROCESSOR
    // ========================================
    console.log("📝 Step 4: Deploying VPayProcessor...");
    const VPayProcessor = await ethers.getContractFactory("VPayProcessor");
    const processor = await upgrades.deployProxy(
        VPayProcessor,
        [ADMIN_ADDRESS, vpusdAddress, FEE_COLLECTOR, MERCHANT_FEE_BPS],
        { initializer: "initialize", kind: "uups" }
    );
    await processor.waitForDeployment();
    const processorAddress = await processor.getAddress();
    console.log("✅ VPayProcessor deployed at:", processorAddress, "\n");

    // ========================================
    // 5. DEPLOY BRIDGE HUB
    // ========================================
    console.log("📝 Step 5: Deploying VPayBridgeHub...");
    const VPayBridgeHub = await ethers.getContractFactory("VPayBridgeHub");
    const bridge = await upgrades.deployProxy(
        VPayBridgeHub,
        [ADMIN_ADDRESS, vpusdAddress, BRIDGE_FEE_BPS, DAILY_RATE_LIMIT],
        { initializer: "initialize", kind: "uups" }
    );
    await bridge.waitForDeployment();
    const bridgeAddress = await bridge.getAddress();
    console.log("✅ VPayBridgeHub deployed at:", bridgeAddress, "\n");

    // ========================================
    // 6. DEPLOY TREASURY
    // ========================================
    console.log("📝 Step 6: Deploying VPayTreasury...");
    const VPayTreasury = await ethers.getContractFactory("VPayTreasury");
    const treasury = await upgrades.deployProxy(
        VPayTreasury,
        [ADMIN_ADDRESS, vpusdAddress],
        { initializer: "initialize", kind: "uups" }
    );
    await treasury.waitForDeployment();
    const treasuryAddress = await treasury.getAddress();
    console.log("✅ VPayTreasury deployed at:", treasuryAddress, "\n");

    // ========================================
    // 7. DEPLOY GOVERNANCE
    // ========================================
    console.log("📝 Step 7: Deploying VPayGovernance...");
    const VPayGovernance = await ethers.getContractFactory("VPayGovernance");
    const governance = await upgrades.deployProxy(
        VPayGovernance,
        [ADMIN_ADDRESS, [deployer.address], 1], // Single signer for testnet
        { initializer: "initialize", kind: "uups" }
    );
    await governance.waitForDeployment();
    const governanceAddress = await governance.getAddress();
    console.log("✅ VPayGovernance deployed at:", governanceAddress, "\n");

    // ========================================
    // 8. CONFIGURE ROLES & PERMISSIONS
    // ========================================
    console.log("📝 Step 8: Configuring roles and permissions...");

    // Grant MINTER_ROLE to vault
    const MINTER_ROLE = await vpusd.MINTER_ROLE();
    await vpusd.grantRole(MINTER_ROLE, vaultAddress);
    console.log("   ✓ Granted MINTER_ROLE to HybridVault");

    // Set compliance oracle in VPUSD
    await vpusd.setComplianceOracle(complianceAddress);
    console.log("   ✓ Set compliance oracle in VPUSD");

    // Set compliance oracle in processor
    await processor.setComplianceOracle(complianceAddress);
    console.log("   ✓ Set compliance oracle in VPayProcessor\n");

    // ========================================
    // 9. SUMMARY
    // ========================================
    console.log("✅ ========================================");
    console.log("   DEPLOYMENT COMPLETE!");
    console.log("   ========================================\n");

    const deploymentSummary = {
        network: network.name,
        chainId: network.chainId.toString(),
        deployer: deployer.address,
        contracts: {
            VeritasPayUSD: vpusdAddress,
            HybridVault: vaultAddress,
            VPayCompliance: complianceAddress,
            VPayProcessor: processorAddress,
            VPayBridgeHub: bridgeAddress,
            VPayTreasury: treasuryAddress,
            VPayGovernance: governanceAddress
        },
        timestamp: new Date().toISOString()
    };

    console.log("📋 Deployment Summary:");
    console.log(JSON.stringify(deploymentSummary, null, 2));
    console.log("\n");

    // Save deployment info
    const fs = require("fs");
    const deploymentsDir = "./deployments";
    if (!fs.existsSync(deploymentsDir)) {
        fs.mkdirSync(deploymentsDir);
    }
    fs.writeFileSync(
        `${deploymentsDir}/${network.name}-${Date.now()}.json`,
        JSON.stringify(deploymentSummary, null, 2)
    );

    console.log("💾 Deployment info saved to deployments directory\n");
    console.log("🎉 Next steps:");
    console.log("   1. Verify contracts on block explorer");
    console.log("   2. Add collateral tokens to HybridVault");
    console.log("   3. Configure payment corridors");
    console.log("   4. Test payment flows\n");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
