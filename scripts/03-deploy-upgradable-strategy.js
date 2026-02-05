const prompt = require('prompt');
const hre = require("hardhat");
const { type2Transaction } = require('./utils.js');

async function main() {
  console.log("Upgradable strategy deployment.");
  console.log("Specify a the vault address, and the strategy implementation's name");
  prompt.start();
  const addresses = require("../test/test-config.js");

  const {vaultAddr, strategyName} = await prompt.get(['vaultAddr', 'strategyName']);

  const StrategyImpl = artifacts.require(strategyName);
  const impl = await type2Transaction(StrategyImpl.new);

  console.log("Implementation deployed at:", impl.creates);
  await new Promise(r => setTimeout(r, 2000))

  const StrategyProxy = artifacts.require('StrategyProxy');
  const proxy = await type2Transaction(StrategyProxy.new, impl.creates);

  console.log("Proxy deployed at:", proxy.creates);
  await new Promise(r => setTimeout(r, 2000))

  const strategy = await StrategyImpl.at(proxy.creates);
  await type2Transaction(strategy.initializeStrategy, addresses.Storage, vaultAddr);

  console.log("Deployment complete. New strategy deployed and initialised at", proxy.creates);
  console.log(
`{
  "vault": "${vaultAddr}",
  "newStrategy": "${proxy.creates}"
}`
  )
  try {
    await hre.run("verify:verify", {address: impl.creates}); 
  } catch (e) {
    console.log("Verification failed:", e);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
