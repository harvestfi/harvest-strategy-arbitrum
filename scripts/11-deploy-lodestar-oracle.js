const prompt = require('prompt');
const hre = require("hardhat");
const { type2Transaction } = require('./utils.js');
const ImplContract = artifacts.require("PriceOracleProxyETH");

async function main() {
  console.log("New Lodestar Oracle deployment.");
  prompt.start();

  // const impl = await type2Transaction(
  //   ImplContract.new,
  //   "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
  //   "0xFdB631F5EE196F0ed6FAa767959853A9F217697D",
  //   "0x2193c45244AF12C280941281c8aa67dD08be0a64",
  //   "0xeA0a73c17323d1a9457D722F10E7baB22dc0cB83",
  //   "0x5ba0828A5488c20a9C6521a90ecc9c49e5390604"
  // );

  // console.log("Deployment complete. Implementation deployed at:", impl.creates);

  // await hre.run("verify:verify", {
  //   address: "0xBB23e58b16666C23e0Efd94cE87F2B9DdA38D216",
  //   constructorArguments: [
  //     "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
  //     "0xFdB631F5EE196F0ed6FAa767959853A9F217697D",
  //     "0x2193c45244AF12C280941281c8aa67dD08be0a64",
  //     "0xeA0a73c17323d1a9457D722F10E7baB22dc0cB83",
  //     "0x5ba0828A5488c20a9C6521a90ecc9c49e5390604"
  //   ]
  // });

  const contract = await ImplContract.at("0xBB23e58b16666C23e0Efd94cE87F2B9DdA38D216");
  await type2Transaction(
    contract._setAggregators,
    [
      "0x5d27cFf80dF09f28534bb37d386D43aA60f88e25",
      "0xD12d43Cdf498e377D3bfa2c6217f05B466E14228",
      "0xf21Ef887CB667f84B8eC5934C1713A7Ade8c38Cf",
      "0x4C9aAed3b8c443b4b634D1A189a5e25C604768dE",
      "0x9365181A7df82a1cC578eAE443EFd89f00dbb643",
      "0xC37896BF3EE5a2c62Cdbd674035069776f721668",
      "0x4987782da9a63bC3ABace48648B15546D821c720",
      "0x2193c45244AF12C280941281c8aa67dD08be0a64",
      "0x8991d64fe388fA79A4f7Aa7826E8dA09F0c3C96a",
      "0xfECe754D92bd956F681A941Cef4632AB65710495",
      "0x79B6c5e1A7C0aD507E1dB81eC7cF269062BAb4Eb",
      "0x39c27DfdC9364a976926a820c8CAA8Fd035D0727",
      "0x929cC7EBa600CcB3FAf5494210206C93219CcB28",
      "0x1ca530f02DD0487cef4943c674342c5aEa08922F",
    ],
    [
      "0xe8B592D624BA7536e7e93cADF1B9cBf25fCc9760",
      "0x0809E3d38d1B4214958faf06D8b1B1a2b73f2ab8",
      "0x47E55cCec6582838E173f252D08Afd8116c2202d",
      "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",
      "0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7",
      "0xd0C7101eACbB49F3deCcCc166d238410D6D46d57",
      "0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB",
      "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
      "0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6",
      "0xb523AE262D20A936BC152e6023996e46FDC2A95D",
      "0xDB98056FecFff59D032aB628337A4887110df3dB",
      "0x66853E19d73c0F9301fe099c324A1E9726953433",
      "0x87121F6c9A9F6E90E59591E4Cf4804873f54A95b",
      "0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",
    ],
    [0,0,0,0,0,0,0,0,0,1,0,0,0,0]
  )
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
