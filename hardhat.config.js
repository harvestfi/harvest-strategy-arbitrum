require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-web3");
require("@nomiclabs/hardhat-ethers");
require('hardhat-contract-sizer');

const secret = require('./dev-keys.json');

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      accounts: {
        mnemonic: secret.mnemonic,
      },
      chainId: 42161,
      blockGasLimit: 100e6,
      forking: {
        url: `https://arb-mainnet.g.alchemy.com/v2/${secret.alchemyKey}`,
        // blockNumber: 79985280, // <-- edit here
      },
    },
    mainnet: {
      url: `https://arb-mainnet.g.alchemy.com/v2/${secret.alchemyKey}`,
      accounts: {
        mnemonic: secret.mnemonic,
      },
    },
  },
  solidity: {
    compilers: [
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  mocha: {
    timeout: 2000000
  },
  etherscan: {
    apiKey: secret.etherscanAPI,
  },
  contractSizer: {
    alphaSort: false,
    disambiguatePaths: false,
    runOnCompile: false,
    strict: false,
  },
};
