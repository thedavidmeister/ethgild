import chai from "chai";
import { solidity } from "ethereum-waffle";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { expectedReferencePrice, deployERC20PriceOracleVault } from "../util";

chai.use(solidity);
const { assert } = chai;

export const usdDecimals = 8;
export const xauDecimals = 8;

describe("oracle construction", async function () {
  it("should set reference price", async function () {
    const [_vault, _erc20, priceOracle, basePriceOracle, quotePriceOracle] =
      await deployERC20PriceOracleVault();

    // ETHUSD as of 2022-06-30
    await basePriceOracle.setDecimals(usdDecimals);
    await basePriceOracle.setRoundData(1, {
      startedAt: BigNumber.from(Date.now()).div(1000),
      updatedAt: BigNumber.from(Date.now()).div(1000),
      answer: "106045000000",
      answeredInRound: 1,
    });

    // XAUUSD as of 2022-06-30
    await quotePriceOracle.setDecimals(xauDecimals);
    await quotePriceOracle.setRoundData(1, {
      startedAt: BigNumber.from(Date.now()).div(1000),
      updatedAt: BigNumber.from(Date.now()).div(1000),
      answer: "181832000000",
      answeredInRound: 1,
    });

    const actualPrice = await priceOracle.price();
    //5832031765585816 //583203176558581547
    assert(
      actualPrice.eq(expectedReferencePrice),
      `wrong price ${expectedReferencePrice} ${actualPrice}`
    );
  });
});
