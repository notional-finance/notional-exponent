import { createConfig } from "ponder";

import { AddressRegistryAbi } from "./abis/AddressRegistryAbi";
import { ITradingModuleAbi } from "./abis/ITradingModuleAbi";

export default createConfig({
  chains: { mainnet: { id: 1, rpc: process.env.PONDER_RPC_URL_1!, ethGetLogsBlockRange: 2000 } },
  contracts: {
    AddressRegistry: {
      chain: "mainnet",
      address: "0xe335d314BD4eF7DD44F103dC124FEFb7Ce63eC95",
      abi: AddressRegistryAbi,
      startBlock: 23027728,
    },
    TradingModule: {
      chain: "mainnet",
      address: "0x594734c7e06C3D483466ADBCe401C6Bd269746C8",
      abi: ITradingModuleAbi,
      startBlock: 23027728,
    },
  },
});
