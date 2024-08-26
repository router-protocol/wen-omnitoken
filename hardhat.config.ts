import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import path from "path";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.25",
    settings: {
      viaIR: true,
      // remappings: [
      //   `solmate/=${path.join(__dirname, "node_modules/solmate/src/")}`,
      // ],
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  paths: {
    sources: "src",
  },
};

export default config;
