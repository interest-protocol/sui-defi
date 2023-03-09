# [Interest Protocol](https://sui.interestprotocol.com/)

 <p> <img width="50px"height="50px" src="./assets/logo.png" /></p> 
 
 IPX Lending and DEX modules on the [Sui](https://sui.io/) Network.  
  
## Quick start  
  
Make sure you have the latest version of the Sui binaries installed on your machine

[Instructions here](https://docs.sui.io/devnet/build/install)

### Run tests

```bash
  sui move test
```

### Publish

```bash
  sui client publish --gas-budget 50000
```

## Functionality

### Lending (WIP)

The Interest Protocol Lending Protocol allows users to borrow and lend cryptocurrencies.

The lending protocol providers the following core functions

- **deposit:** it allows users to put collateral to start earning interest rate + rewards
- **withdraw:** it allows users to remove their collateral
- **borrow:** it allows users to borrow crypto using their deposits as collateral. This allows them to open short/long positions
- **repay:** it allows users to repay their loans

### DEX

The Interest Protocol DEX allows users to create pools, add/remove liquidity and trade.

The DEX supports two types of pools denoted as:

- **Volatile:** `k = x * y` popularized by [Uniswap](https://uniswap.org/whitepaper.pdf)
- **Stable:** `k = yx^3 + xy^3` inspired by Curve's algorithm.

> The DEX will route the trade to the most profitable pool (volatile vs
> stable).

- Add/Remove Liquidity
- Swap: Pool<BTC, Ether> | Ether -> BTC | BTC -> Ether
- Create Pool: Users can only create volatile pools
- One Hop Swap: Pool<BTC, Ether> & Pool<Ether, USDC> | BTC -> Ether -> USDC | USDC -> Ether -> BTC
- Two Hop Swap: Pool<BTC, Ether> & Pool<Ether, USDC> & Pool<Sui, USDC> | BTC -> Ether -> USDC -> Sui | Sui -> USDC -> Ether -> BTC
- Farms to deposit VLPCoins and SLPCoins to farm IPX tokens
- Flash loans

**Future Features**

- TWAP Oracle
- [Concentrated Liquidity](https://uniswap.org/whitepaper-v3.pdf)

### IPX Coin

It is the governance coin of the protocol and it is minted as rewards by the Masterchef and lending modules. This coin will power the DAO in the future.

### DNR Coin

It is a stablecoin created by the lending module. It is pegged to he USD dollars. Users pay a constant interest rate to borrow it.

## Live

Go to [here (Sui Interest Protocol)](https://sui.interestprotocol.com/) and see what we have prepared for you

## Contact Us

- Twitter: [@interest_dinero](https://twitter.com/interest_dinero)
- Discord: https://discord.gg/interestprotocol
- Telegram: https://t.me/interestprotocol
- Email: [contact@interestprotocol.com](mailto:contact@interestprotocol.com)
- Medium: [@interestprotocol](https://medium.com/@interestprotocol)
