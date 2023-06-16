# [Interest Protocol](https://sui.interestprotocol.com/)

 <p> <img width="50px"height="50px" src="./assets/logo.png" /></p> 
 
A set of experimental Contracts for the [Sui](https://sui.io/) Network.  
Once these modules go live, they are moved to their own repos.
  
## Quick start  
  
Make sure you have the latest version of the Sui binaries installed on your machine

[Instructions here](https://docs.sui.io/devnet/build/install)

### Run tests

**To run the tests on the dex directory**

```bash
  cd clamm
  sui move test
```

### Publish

```bash
  cd clamm
  sui client publish --gas-budget 500000000
```

## Repo Structure

- **library:** It contains utility functions that are used by other modules
- **airdrop:** It contains the module to airdrop the IPX governance token to whitelisted accounts
- **examples:** A myriad of examples on how to interact with various modules
- **audits** It contains code audits
- **i256** A library to
- **clamm** UniswapV3 in Move (WIP)

## Functionality

### CLAMM

The Interest Protocol Concentrated Liquidity AMM

Users will be able to perform all traditional functions of an AMM

**Innovation**: LP providers will be able to automatically list their out of money liquidity positions on a Money Market to earn yield. The protocol will withdraw the collateral once the liquidity becomes on the money.

### Airdrop

It contains the airdrop module for the IPX governance coin. It distributes the tokens linearly to whitelisted addresses using a merkle tree.

### Examples

- **airdrop-tree:** A typescript implementation of a merkle tree to use with the airdrop module

## Live

Go to [here (Sui Interest Protocol)](https://sui.interestprotocol.com/) and see what we have prepared for you

## Contact Us

- Twitter: [@interest_dinero](https://twitter.com/interest_dinero)
- Discord: https://discord.gg/interestprotocol
- Telegram: https://t.me/interestprotocol
- Email: [contact@interestprotocol.com](mailto:contact@interestprotocol.com)
- Medium: [@interestprotocol](https://medium.com/@interestprotocol)
