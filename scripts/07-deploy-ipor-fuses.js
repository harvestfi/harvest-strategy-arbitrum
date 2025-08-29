const prompt = require('prompt');
const hre = require("hardhat");
const { type2Transaction } = require('./utils.js');
const BlanceFuseContr = artifacts.require('Erc4626BalanceFuse');
const SupplyFuseContr = artifacts.require('Erc4626SupplyFuse');


async function main() {
  console.log("Deploy a set of IPOR Fuses");
  console.log("Specify the sequential marketId");
  prompt.start();

  const {id} = await prompt.get(['id']);

  const balanceFuse = await type2Transaction(BlanceFuseContr.new, id);
  console.log("Balance Fuse deployed at:", balanceFuse.creates);
  await new Promise(r => setTimeout(r, 2000))

  const supplyFuse = await type2Transaction(SupplyFuseContr.new, id);
  console.log("Supply Fuse deployed at:", supplyFuse.creates);
  await new Promise(r => setTimeout(r, 2000))

  console.log("Deployment complete.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });