# [Interest Protocol](https://sui.interestprotocol.com/)

 <p> <img width="50px"height="50px" src="./assets/logo.png" /></p> 
 
A set of experimental Contracts for the [Sui](https://sui.io/) Network.  
  
## Quick start  
  
Make sure you have the latest version of the Sui binaries installed on your machine

[Instructions here](https://docs.sui.io/devnet/build/install)

### Run tests

**To run the tests on the dex directory**

```bash
  cd dex
  sui move test
```

### Publish

```bash
  cd dex
  sui client publish --gas-budget 500000000
```

## Repo Structure

- **dex:** It contains the logic for users to swap, add/remove liquidity and create pools
- **whirlpool:** It contains the logic for users to borrow and lend coins
- **ipx:** The governance token of Interest Protocol
- **sui-dollar:** The stable coin of Interest Protocol
- **library:** It contains utility functions that are used by other modules
- **airdrop:** It contains the module to airdrop the IPX governance token to whitelisted accounts
- **examples:** A myriad of examples on how to interact with various modules
- **audits** It contains code audits
- **i256** A library to

## Functionality

### DEX

> This code has been [audited](https://github.com/interest-protocol/sui-defi/blob/main/audits/Interest%20Protocol%20DEX%20Smart%20Contract%20Audit%20Report.pdf) by [MoveBit](https://movebit.xyz/)

The Interest Protocol DEX allows users to create pools, add/remove liquidity and trade.

The DEX supports two types of pools denoted as:

- **Volatile:** `k = x * y` popularized by [Uniswap](https://uniswap.org/whitepaper.pdf)
- **Stable:** `k = yx^3 + xy^3` inspired by Curve's algorithm.

> The DEX will route the trade to the most profitable pool (volatile vs
> stable).

- Create Pool: Users can only create volatile & stable pools
- Add/Remove Liquidity
- Swap: Pool<BTC, Ether> | Ether -> BTC | BTC -> Ether
- One Hop Swap: Pool<BTC, Ether> & Pool<Ether, USDC> | BTC -> Ether -> USDC | USDC -> Ether -> BTC
- Two Hop Swap: Pool<BTC, Ether> & Pool<Ether, USDC> & Pool<Sui, USDC> | BTC -> Ether -> USDC -> Sui | Sui -> USDC -> Ether -> BTC
- Farms to deposit LPCoins to farm IPX tokens
- Flash loans
- TWAP Oracle

### IPX Coin

It is the governance coin of the protocol and it is minted as rewards by the Masterchef and lending modules. This coin will power the DAO in the future.

### Whirlpool

The Interest Protocol Lending Protocol allows users to borrow and lend cryptocurrencies.

The lending protocol providers the following core functions

- **deposit:** it allows users to put collateral to start earning interest rate + rewards
- **withdraw:** it allows users to remove their collateral
- **borrow:** it allows users to borrow crypto using their deposits as collateral. This allows them to open short/long positions
- **repay:** it allows users to repay their loans

### SUID Coin

It is a stablecoin created by the lending module. It is pegged to he USD dollars. Users pay a constant interest rate to borrow it.

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
