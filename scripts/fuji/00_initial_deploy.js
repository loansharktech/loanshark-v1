const chalk = require("chalk");
const { deployController } = require("../tasks/deployController");
const { deployFlasher } = require("../tasks/deployFlasher");
const { deployFliquidator } = require("../tasks/deployFliquidator");
const { deployFujiAdmin } = require("../tasks/deployFujiAdmin");
const { deployFujiERC1155 } = require("../tasks/deployFujiERC1155");
const { deployFujiOracle } = require("../tasks/deployFujiOracle");
const { deployProvider } = require("../tasks/deployProvider");
const { deploySwapper } = require("../tasks/deploySwapper");
const { deployVault } = require("../tasks/deployVault");
const { deployVaultHarvester } = require("../tasks/deployVaultHarvester");
const { updateController } = require("../tasks/updateController");
const { updateFlasher } = require("../tasks/updateFlasher");
const { updateFujiAdmin } = require("../tasks/updateFujiAdmin");
const { updateFujiERC1155 } = require("../tasks/updateFujiERC1155");
const { updateFujiFliquidator } = require("../tasks/updateFujiFliquidator");
const { updateVault } = require("../tasks/updateVault");
const { setDeploymentsPath, network } = require("../utils");
const { ASSETS, SUSHI_ROUTER_ADDR } = require("./consts");

const deployContracts = async () => {
  console.log("\n\n 📡 Deploying...\n");

  // Functional Contracts
  const treasury = "0xe71fa402007FAD17dA769D1bBEfA6d0790fCe2c7";
  const fujiadmin = await deployFujiAdmin();
  const fliquidator = await deployFliquidator();
  const flasher = await deployFlasher();
  const controller = await deployController();
  const f1155 = await deployFujiERC1155();
  const oracle = await deployFujiOracle([
    Object.values(ASSETS).map((asset) => asset.address),
    Object.values(ASSETS).map((asset) => asset.oracle),
  ]);

  // Provider Contracts
  const aave = await deployProvider("ProviderAave");
  const compound = await deployProvider("ProviderCompound");
  // const dydx = await deployProvider("ProviderDYDX");
  // const ironBank = await deployProvider("ProviderIronBank");

  // Deploy Core Money Handling Contracts
  const vaultharvester = await deployVaultHarvester();
  const swapper = await deploySwapper();
  //
  // const vaultdai = await deployVault("VaultETHDAI", [
  //   fujiadmin,
  //   oracle,
  //   ASSETS.ETH.address,
  //   ASSETS.DAI.address,
  // ]);
  const vaultusdc = await deployVault("VaultAVAXUSDC", [
    fujiadmin,
    oracle,
    ASSETS.AVAX.address,
    ASSETS.USDC.address,
  ]);
  const vaultusdt = await deployVault("VaultAVAXUSDT", [
    fujiadmin,
    oracle,
    ASSETS.AVAX.address,
    ASSETS.USDT.address,
  ]);

  // General Plug-ins and Set-up Transactions
  await updateFujiAdmin(fujiadmin, {
    flasher,
    fliquidator,
    treasury,
    controller,
    vaultharvester,
    swapper,
  });
  await updateFujiFliquidator(fliquidator, { fujiadmin, oracle, swapper: SUSHI_ROUTER_ADDR });
  await updateFlasher(flasher, fujiadmin);
  await updateController(controller, fujiadmin);
  await updateFujiERC1155(f1155, [vaultusdc, vaultusdt, fliquidator]);

  //await updateFujiERC1155(f1155, [vaultdai, vaultusdc, vaultusdt, fliquidator]);

  // Vault Set-up
  // await updateVault("VaultETHDAI", vaultdai, {
  //   providers: [compound, aave],
  //   //providers: [compound, aave, dydx, ironBank],
  //   fujiadmin,
  //   f1155,
  // });
  await updateVault("VaultAVAXUSDC", vaultusdc, {
    providers: [compound, aave],
    //providers: [compound, aave, dydx, ironBank],
    fujiadmin,
    f1155,
  });
  await updateVault("VaultAVAXUSDT", vaultusdt, {
    providers: [compound, aave],
    //providers: [compound, aave, dydx, ironBank],
    fujiadmin,
    f1155,
  });

  console.log("Finished!");
};

const main = async () => {
  console.log("network: ", network);
  if (network !== "fuji") {
    throw new Error("Please set 'NETWORK=fuji' in ./packages/hardhat/.env");
  }

  await setDeploymentsPath("core");
  await deployContracts();
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(chalk.red(`\n${error}\n`));
    process.exit(1);
  });
