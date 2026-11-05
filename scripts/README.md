# Factory Scripts

The scripts allow for a whitelisted party to deploy components of Harvest, such as vaults, pools, and strategies.
Important:
1. Set gas limit to VERY high (~9,000,000)
2. Deployments are pretty expensive: please make sure there is enough Ether (1 ETH, or more for one deployment).
3. Always simulate the transaction first by appending the flag `--network hardhat` (or omitting `--network`)
4. Once simulation is successful, use the mainnet flag: `--network mainnet`
5. Take prerequisites into account (such as, creating a position token for Uniswap V3)

Latest factory addresses are located in `./test/test-config.js`, under `Factory`.

### Regular vault (with upgradable strategy)

Deploying a new vault with the standard reward PotPool, using an upgradable strategy implementation (that was deployed earlier):

```
npx hardhat run ./scripts/01-deploy-vault-regular-with-upgradable-strategy.js --network hardhat
Regular vault deployment with upgradable strategy.
> Prerequisite: deploy upgradable strategy implementation
Specify a unique ID (for the JSON), vault's underlying token address, and upgradable strategy implementation address
prompt: id:  test_YEL_WETH
prompt: underlying:  0xc83cE8612164eF7A13d17DDea4271DD8e8EEbE5d
prompt: strategyImpl:  0xBa6b43ae8Ea74a5D7F4e65904aAf80bFB1Bc59CB
======
test_YEL_WETH: {
  "Underlying": "0xc83cE8612164eF7A13d17DDea4271DD8e8EEbE5d",
  "NewVault": "0xd1c9CE4C3D87B2B9dDc500F6f47E65FB7d426Ac2",
  "NewStrategy": "0x908B743A405F23Ea5877C14E32d76B1B7A97369D",
  "NewPool": "0x9b2C5A51adac687867C19Bd76656702b47A24e16"
}
======
Deployment complete. Add the JSON above to `harvest-api` (https://github.com/harvest-finance/harvest-api/blob/master/data/mainnet/addresses.json) repo and add entries to `tokens.js` and `pools.js`.
```

### Regular vault (no strategy)

Deploying a regular vault with the standard reward PotPool (no pre-defined strategy, but can be added later by Governance):

```
npx hardhat run ./scripts/02-deploy-vault-regular.js --network hardhat
Regular vault deployment (no strategy).
Specify a unique ID (for the JSON) and the vault's underlying token address
prompt: id:  dai_test
prompt: underlying:  0x6B175474E89094C44Da98b954EedeAC495271d0F
======
dai_test: {
  "Underlying": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
  "NewVault": "0xd1c9CE4C3D87B2B9dDc500F6f47E65FB7d426Ac2",
  "NewStrategy": "0x0000000000000000000000000000000000000000",
  "NewPool": "0x9b2C5A51adac687867C19Bd76656702b47A24e16"
}
======
Deployment complete. Add the JSON above to `harvest-api` (https://github.com/harvest-finance/harvest-api/blob/master/data/mainnet/addresses.json) repo and add entries to `tokens.js` and `pools.js`.
```

### Upgrade the live Morpho V2 strategies

Deploys new implementations for the three live Morpho Vault V2 strategies (Gauntlet Balanced V2, Gauntlet Prime V2, Steakhouse High Yield V2) and writes the Safe Transaction Builder files for governance. It only deploys: the proxies are not touched until the Safe sends the transactions. The plan itself lives in `scripts/morpho-v2-upgrade-plan.js`, and `test/morpho/v2/upgrade-rehearsal.js` runs that same plan on a fork.

```
npx hardhat run ./scripts/12-prepare-morpho-v2-upgrade.js --network hardhat
npx hardhat run ./scripts/12-prepare-morpho-v2-upgrade.js --network mainnet
```

On `--network hardhat` it is a dry run against the fork. The three strategies have to exist at the fork block, so set `blockNumber` in `hardhat.config.js` to a recent one first (521420000 or later). Options (environment variables): `ONLY=GC,GP` to limit the run, `GC_IMPL` / `GP_IMPL` / `SHHY_IMPL` to reuse an implementation instead of deploying one, `VERIFY_REUSED=1` to verify a reused one again, `OUT` for where the files go (default `./safe-transactions`).

Governance then executes, as the Safe: `morpho-v2-upgrade-1-schedule.json`, and strictly after the 12h timelock `morpho-v2-upgrade-2-upgrade.json`. To go back, `morpho-v2-upgrade-rollback-schedule.json`, then the second file again after another 12h. `upgrade()` installs whatever is scheduled, so check `nextImplementation()` on each proxy before signing the second file.

The upgrade drops MORPHO from the reward tokens of the three strategies. Until it has run, MORPHO sent to one of them blocks that vault's deposits and withdrawals; the stopgap is `strategy.salvage(recipient, MORPHO, balance)` from the Safe on that strategy (`Controller.salvageStrategy` does not reach it).
