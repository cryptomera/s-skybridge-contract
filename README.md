# Sky-Bridge Contract
## start
npm install

## compile smart contracts and export abi
npx hardhat compile

## install abigen-tool

  https://www.metachris.com/2021/05/creating-go-bindings-for-ethereum-smart-contracts/

## export goabi
  npx hardhat run scripts/abigogen.ts

## test smart contracts

  npx hardhat test

## deploy smart contract on mainnet

  You should define following constants before deploy contract
  reward token address
  price per btc
  BTC pool address
  Wrapped ether address
  existing BTC amount for float

  ### command
  npx hardhat run --network mainnet script/deploy.ts

## upgrade proxy

  You should input proxy address in .env file
  PROXY=0x123...
  ### command
  npx hardhat run --network mainnet script/upgrade_proxy.ts