import type { HardhatUserConfig }  from "hardhat/types";
import "@nomiclabs/hardhat-waffle";
import "hardhat-typechain";
import 'hardhat-contract-sizer';

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      blockGasLimit: 100000000,
      allowUnlimitedContractSize: true,
    }
  },
  solidity: {
    compilers: [
      { version: "0.8.5", settings: {} },
    ],
  },
};
export default config;