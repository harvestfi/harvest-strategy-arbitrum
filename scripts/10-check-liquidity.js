const BigNumber = require("bignumber.js");
const IERC4626 = artifacts.require('contracts/base/interface/IERC4626.sol:IERC4626');

async function main() {
  console.log("Check Morpho Liquidity");

  const contract = await IERC4626.at("0xa60643c90A542A95026C0F1dbdB0615fF42019Cf")
  
  while (true) {
    const available = new BigNumber(await contract.maxWithdraw("0xcB7500b629D75d004CE7eE8B8C724231b1f76b61"));
    console.log(available.div(1e6).toFixed())
    await new Promise(r => setTimeout(r, 2000))
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });