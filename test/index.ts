import { AddressZero } from "@ethersproject/constants";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";


describe("Greeter", function () {
  it("Should return the new greeting once it's changed", async function () {
    const SwapContractV1 = await ethers.getContractFactory("SwapContractV1");
    const SwapContractV2 = await ethers.getContractFactory("SwapContractV2");
    const addr = AddressZero;
    const swapV1 = await upgrades.deployProxy(SwapContractV1, [
      addr,
      addr,
      addr,
      addr,
      addr,
      addr,
      0
    ], {initializer: 'initialize'});
    console.log("swapv1=>", swapV1.address);
    const swapV2 = await upgrades.upgradeProxy(swapV1.address, SwapContractV2);
    console.log("swapv2=>", swapV2.address);
  });
});
