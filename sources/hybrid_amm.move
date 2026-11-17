/// Module: atoadex_core::hybrid_amm
/// AtoaDEX v1.9.8 — Insured & Circuit-Broken Hybrid AMM & Canonical Fee Router
/// Implements the immutable 35 / 20 / 15 / 19 / 5 / 6 swap-fee split and
/// enforces 10.00% per-epoch outflow protection + 24-hour whale queue routing.
module atoadex_core::hybrid_amm {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::event;
    use atoadex_core::circuit_breaker::{
        Self,
        GlobalBreakerRegistry,
        PoolCircuitBreaker,
    };
    use atoadex_core::whale_queue::{Self, QueuedWithdrawalTicket};

    // === Error Codes ===
    const EZeroLiquidity: u64 = 4001;
    const EInsufficientOutput: u64 = 4002;
    const EInvalidFeeBps: u64 = 4003;
    const ECircuitBreakerTripped: u64 = 4004;
    const EWrongPoolTicket: u64 = 4005;

    // === Canonical v1.9.8 Fee Split Constants (Total = 10,000 bps = 100.00%) ===
    const FEE_BPS_DENOMINATOR: u64 = 10000;
    /// 35.00% External Liquidity Providers
    const LP_SHARE_BPS: u64 = 3500;
    /// 20.00% veATOA Vote-Escrow Lockers
    const VEATOA_SHARE_BPS: u64 = 2000;
    /// 15.00% Sovereign Locked POL Auto-Compound
    const POL_COMPOUND_BPS: u64 = 1500;
    /// 19.00% Day-1 Open-Market Buyback & Burn (0x0) / rATOA Self-Healing
    const BUYBACK_BURN_BPS: u64 = 1900;
    /// 5.00% Permanent rATOA Insurance Vault Stream
    const INSURANCE_SHARE_BPS: u64 = 500;
    /// 6.00% AtoaDEX Labs Cash OPEX
    const CASH_OPEX_BPS: u64 = 600;

    // === Structs ===

    /// Liquidity Pool holding Token X & Token Y, attached Circuit Breaker, and Fee Vaults
    public struct LiquidityPool<phantom X, phantom Y> has key {
        id: UID,
        reserve_x: Balance<X>,
        reserve_y: Balance<Y>,
        /// Swap fee in basis points (e.g. 2 bps = 0.02% StableSwap, 30 bps = 0.30% Volatile)
        swap_fee_bps: u64,
        total_lp_shares: u64,
        /// Locked Protocol-Owned Liquidity (Immutable Principal — Fees Still Harvestable)
        locked_pol_shares: u64,
        breaker: PoolCircuitBreaker,
        /// Accumulated protocol fee buckets in Token X
        veatoa_fees_x: Balance<X>,
        buyback_burn_fees_x: Balance<X>,
        insurance_fees_x: Balance<X>,
        opex_fees_x: Balance<X>,
    }

    /// Non-transferable / Same-Address-Bound LP Receipt
    public struct LpPositionReceipt has key, store {
        id: UID,
        pool_id: ID,
        original_depositor: address,
        lp_shares: u64,
    }

    // === Events ===

    public struct PoolCreated has copy, drop {
        pool_id: ID,
        swap_fee_bps: u64,
        initial_x: u64,
        initial_y: u64,
    }

    public struct SwapExecuted has copy, drop {
        pool_id: ID,
        amount_in: u64,
        amount_out: u64,
        total_fee_x: u64,
        lp_fee_x: u64,
        veatoa_fee_x: u64,
        pol_compound_x: u64,
        burn_fee_x: u64,
        insurance_fee_x: u64,
        opex_fee_x: u64,
    }

    // === Public Functions ===

    /// Create a new AtoaDEX Hybrid Pool with built-in 10.00% Epoch Circuit Breaker
    public fun create_pool<X, Y>(
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        swap_fee_bps: u64,
        is_genesis_pol: bool,
        ctx: &mut TxContext
    ) {
        let amount_x = coin_x.value();
        let amount_y = coin_y.value();
        assert!(amount_x > 0 && amount_y > 0, EZeroLiquidity);
        assert!(swap_fee_bps <= 500, EInvalidFeeBps); // Max 5.00%

        let pool_uid = object::new(ctx);
        let pool_id = object::uid_to_inner(&pool_uid);
        let initial_shares = amount_x + amount_y;

        let breaker = circuit_breaker::create_pool_breaker(pool_id, initial_shares, ctx);

        let (locked_pol, user_shares) = if (is_genesis_pol) {
            (initial_shares, 0)
        } else {
            (0, initial_shares)
        };

        let pool = LiquidityPool<X, Y> {
            id: pool_uid,
            reserve_x: coin_x.into_balance(),
            reserve_y: coin_y.into_balance(),
            swap_fee_bps,
            total_lp_shares: initial_shares,
            locked_pol_shares: locked_pol,
            breaker,
            veatoa_fees_x: balance::zero<X>(),
            buyback_burn_fees_x: balance::zero<X>(),
            insurance_fees_x: balance::zero<X>(),
            opex_fees_x: balance::zero<X>(),
        };

        event::emit(PoolCreated {
            pool_id,
            swap_fee_bps,
            initial_x: amount_x,
            initial_y: amount_y,
        });

        transfer::share_object(pool);

        if (user_shares > 0) {
            let receipt = LpPositionReceipt {
                id: object::new(ctx),
                pool_id,
                original_depositor: ctx.sender(),
                lp_shares: user_shares,
            };
            transfer::transfer(receipt, ctx.sender());
        };
    }

    /// Swap Token X for Token Y with automatic 35 / 20 / 15 / 19 / 5 / 6 fee routing
    public fun swap_x_to_y<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coin_in: Coin<X>,
        min_amount_out: u64,
        ctx: &mut TxContext
    ): Coin<Y> {
        let amount_in = coin_in.value();
        assert!(amount_in > 0, EZeroLiquidity);

        let mut in_bal = coin_in.into_balance();
        let total_fee = ((amount_in as u128) * (pool.swap_fee_bps as u128)
            / (FEE_BPS_DENOMINATOR as u128)) as u64;

        let fee_bal = in_bal.split(total_fee);
        let (lp_f, ve_f, pol_f, burn_f, ins_f, opex_f) = route_canonical_fees(pool, fee_bal);

        let net_in = in_bal.value();
        let rx = pool.reserve_x.value() as u128;
        let ry = pool.reserve_y.value() as u128;
        assert!(rx > 0 && ry > 0, EZeroLiquidity);

        // Constant-product execution on net input
        let amount_out = (((net_in as u128) * ry) / (rx + (net_in as u128))) as u64;
        assert!(amount_out >= min_amount_out && amount_out < (ry as u64), EInsufficientOutput);

        pool.reserve_x.join(in_bal);
        let out_bal = pool.reserve_y.split(amount_out);

        event::emit(SwapExecuted {
            pool_id: object::id(pool),
            amount_in,
            amount_out,
            total_fee_x: total_fee,
            lp_fee_x: lp_f,
            veatoa_fee_x: ve_f,
            pol_compound_x: pol_f,
            burn_fee_x: burn_f,
            insurance_fee_x: ins_f,
            opex_fee_x: opex_f,
        });

        coin::from_balance(out_bal, ctx)
    }

    /// Standard Withdrawal: Protected by 10.00% Epoch Outflow Cap & Same-Address Lock.
    /// If withdrawal exceeds the 10.00% cap, routes automatically to the 24-Hour Whale Queue.
    public fun withdraw_liquidity<X, Y>(
        registry: &mut GlobalBreakerRegistry,
        pool: &mut LiquidityPool<X, Y>,
        receipt: &mut LpPositionReceipt,
        shares_to_withdraw: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<X>, Coin<Y>) {
        assert!(receipt.pool_id == object::id(pool), EWrongPoolTicket);
        assert!(receipt.original_depositor == ctx.sender(), EWrongPoolTicket);
        assert!(shares_to_withdraw > 0 && shares_to_withdraw <= receipt.lp_shares, EZeroLiquidity);

        let current_tvl = pool.total_lp_shares;
        let allowed = circuit_breaker::check_and_record_outflow(
            registry,
            &mut pool.breaker,
            shares_to_withdraw,
            current_tvl,
            ctx
        );

        if (!allowed) {
            // Automatically queue large withdrawal into 24-Hour Timelocked Whale Queue
            receipt.lp_shares = receipt.lp_shares - shares_to_withdraw;
            whale_queue::queue_large_withdrawal(
                object::id(pool),
                shares_to_withdraw,
                clock,
                ctx
            );
            return (coin::zero<X>(ctx), coin::zero<Y>(ctx))
        };

        let out_x = (((shares_to_withdraw as u128) * (pool.reserve_x.value() as u128))
            / (pool.total_lp_shares as u128)) as u64;
        let out_y = (((shares_to_withdraw as u128) * (pool.reserve_y.value() as u128))
            / (pool.total_lp_shares as u128)) as u64;

        receipt.lp_shares = receipt.lp_shares - shares_to_withdraw;
        pool.total_lp_shares = pool.total_lp_shares - shares_to_withdraw;

        let coin_x = coin::from_balance(pool.reserve_x.split(out_x), ctx);
        let coin_y = coin::from_balance(pool.reserve_y.split(out_y), ctx);
        (coin_x, coin_y)
    }

    /// Claim matured 24-Hour Whale Queue ticket (Same-Address Return Only)
    public fun claim_queued_whale_withdrawal<X, Y>(
   public fun claim_timelocked_whale_withdrawal<X, Y>(
    pool: &mut LiquidityPool<X, Y>,
    ticket: WhaleExitTicket,
    clock: &Clock,
    ctx: &mut TxContext
): (Coin<X>, Coin<Y>) {
    let shares = whale_queue::verify_and_consume_ticket(ticket, clock, ctx)

