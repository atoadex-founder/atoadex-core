Dear Sui Foundation Grants Team,

I am the Founder of AtoaDEX (incorporating in the Philippines as AtoaDEX Labs), building an insured, circuit-broken Hybrid Stablecoin and LST ve(3,3) DEX on Sui targeting Q1 2027 Mainnet launch.

We have published our core open-source Sui Move security and AMM smart contracts on GitHub along with our live interactive Testnet UI preview, and we are applying for a $25,000 USD Milestone-Gated Developer Grant:

1. Per-Epoch Pool Outflow Circuit Breaker (sources/circuit_breaker.move): Hardcodes a 10.00% per-epoch outflow cap per pool (isolating affected pools while keeping 90.00% of liquidity safe, and triggering a global pause if 2 or more pools breach simultaneously).

2. 24-Hour Timelocked Whale Withdrawal Queue and Same-Address Return Lock (sources/whale_queue.move): Eliminates instant single-block drain vectors while preserving smooth institutional withdrawals.

3. Self-Healing 1:1 rATOA Insurance Vault (sources/ratoa_vault.move): Pre-seeded on Day 1 with 2,500,000 $ATOA ($400,000 at IDO price) plus a permanent 5.00% swap-fee allocation to protect Sui stablecoin (AUSD, USDY, BUCK) and 4-Throne LST (haSUI, vSUI, sSUI, afSUI) LPs.

4. Hybrid AMM and Canonical Fee Router (sources/hybrid_amm.move): Enforces our immutable 35 / 20 / 15 / 19 / 5 / 6 swap-fee split.

3-Milestone Deliverables ($25,000 Total):

Milestone 1 ($8,000 | Weeks 1-4): Complete unit tests and deploy core Sui Move modules on Sui Testnet.

Milestone 2 ($9,000 | Weeks 5-8): Deploy veATOA vote-escrow, Bribe-War gauges, and Pyth and 7K/Aftermath aggregator integrations on Sui Testnet.

Milestone 3 ($8,000 | Weeks 9-12): Public Testnet stress-testing and Tier-1 Sui Move audit completion (MoveBit or OtterSec).

Our complete AtoaDEX v1.9.8 Canonical Whitepaper is available immediately upon formal grant review or Mutual NDA.

Founder, AtoaDEX
Email: founder.atoadex@proton.me
Live Website: https://atoadex-founder.github.io/atoadex-web/
Sui Move Code: https://github.com/atoadex-founder/atoadex-core
X Profile: https://x.com/AtoaDEX_Sui

