require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-gas-reporter");
require("solidity-coverage");
require("dotenv").config();

const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY || "0x0000000000000000000000000000000000000000000000000000000000000000";

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  networks: {
    hardhat: {
      chainId: 31337,
      forking: process.env.FORK_MAINNET === "true" ? {
        url: process.env.POLYGON_RPC_URL || "",
      } : undefined,
    },
    // Testnets
    mumbai: {
      url: process.env.POLYGON_MUMBAI_RPC_URL || "",
      accounts: [DEPLOYER_PRIVATE_KEY],
      chainId: 80001,
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: [DEPLOYER_PRIVATE_KEY],
      chainId: 11155111,
    },
    arbitrumSepolia: {
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL || "",
      accounts: [DEPLOYER_PRIVATE_KEY],
      chainId: 421614,
    },
    baseSepolia: {
      url: process.env.BASE_SEPOLIA_RPC_URL || "",
      accounts: [DEPLOYER_PRIVATE_KEY],
      chainId: 84532,
    },
    // Mainnets
    polygon: {
      url: process.env.POLYGON_RPC_URL || "",
      accounts: [DEPLOYER_PRIVATE_KEY],
      chainId: 137,
    },
    arbitrum: {
      url: process.env.ARBITRUM_RPC_URL || "",
      accounts: [DEPLOYER_PRIVATE_KEY],
      chainId: 42161,
    },
    base: {
      url: process.env.BASE_RPC_URL || "",
      accounts: [DEPLOYER_PRIVATE_KEY],
      chainId: 8453,
    },
    avalanche: {
      url: process.env.AVALANCHE_RPC_URL || "",
      accounts: [DEPLOYER_PRIVATE_KEY],
      chainId: 43114,
    },
    ethereum: {
      url: process.env.ETHEREUM_RPC_URL || "",
      accounts: [DEPLOYER_PRIVATE_KEY],
      chainId: 1,
    },
  },
  etherscan: {
    apiKey: {
      polygon: process.env.POLYGONSCAN_API_KEY || "",
      polygonMumbai: process.env.POLYGONSCAN_API_KEY || "",
      arbitrumOne: process.env.ARBISCAN_API_KEY || "",
      arbitrumSepolia: process.env.ARBISCAN_API_KEY || "",
      base: process.env.BASESCAN_API_KEY || "",
      baseSepolia: process.env.BASESCAN_API_KEY || "",
      avalanche: process.env.SNOWTRACE_API_KEY || "",
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      sepolia: process.env.ETHERSCAN_API_KEY || "",
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    outputFile: "gas-report.txt",
    noColors: true,
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  mocha: {
    timeout: 200000,
  },
};
