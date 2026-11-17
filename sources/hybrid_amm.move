module atoadex_core::hybrid_amm {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::event;
    use atoadex_core::circuit_breaker::{Self, CircuitBreakerState};
    use atoadex_core::whale_queue::{Self, QueuedWithdrawalTicket};

    const EZeroAmount: u64 = 4001;
    const EInsufficientLiquidity: u64 = 4002;
    const ESlippageExceeded: u64 = 4003;

    const TOTAL_FEE_BPS: u64 = 8; // 0.08% blended fee
    const BPS_DENOM: u64 = 10000;

    public struct LiquidityPool<phantom X, phantom Y> has key {
        id: UID,
        reserve_x: Balance<X>,
        reserve_y: Balance<Y>,
        fee_x: Balance<X>,
        fee_y: Balance<Y>,
        total_lp_shares: u64,
        is_stable: bool,
        breaker: CircuitBreakerState,
    }

    public struct LPPosition<phantom X, phantom Y> has key, store {
        id: UID,
        pool_id: ID,
        shares: u64,
    }

    public struct SwapExecuted has copy, drop {
        pool_id: ID,
        amount_in: u64,
        amount_out: u64,
        fee_taken: u64,
    }

    public fun create_pool<X, Y>(
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        is_stable: bool,
        clock: &Clock,
        ctx: &mut TxContext
    ): LPPosition<X, Y> {
        let val_x = coin_x.value();
        let val_y = coin_y.value();
        assert!(val_x > 0 && val_y > 0, EZeroAmount);

        let initial_shares = ((val_x as u128) * (val_y as u128)).sqrt() as u64;
        let tvl_ref = val_x + val_y;
        let pool_uid = object::new(ctx);
        let pool_id = pool_uid.to_inner();

        let pool = LiquidityPool<X, Y> {
            id: pool_uid,
            reserve_x: coin_x.into_balance(),
            reserve_y: coin_y.into_balance(),
            fee_x: balance::zero<X>(),
            fee_y: balance::zero<Y>(),
            total_lp_shares: initial_shares,
            is_stable,
            breaker: circuit_breaker::new(tvl_ref, clock),
        };
        transfer::share_object(pool);

        LPPosition<X, Y> {
            id: object::new(ctx),
            pool_id,
            shares: initial_shares,
        }
    }

    public fun swap_x_to_y<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        coin_in: Coin<X>,
        min_out: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<Y> {
        let amount_in = coin_in.value();
        assert!(amount_in > 0, EZeroAmount);

        let fee_amount = (amount_in * TOTAL_FEE_BPS) / BPS_DENOM;
        let net_in = amount_in - fee_amount;

        let mut bal_in = coin_in.into_balance();
        let fee_bal = bal_in.split(fee_amount);
        pool.fee_x.join(fee_bal);

        let rx = pool.reserve_x.value() as u128;
        let ry = pool.reserve_y.value() as u128;
        assert!(rx > 0 && ry > 0, EInsufficientLiquidity);

        let amount_out = (((net_in as u128) * ry) / (rx + (net_in as u128))) as u64;
        assert!(amount_out >= min_out && amount_out > 0, ESlippageExceeded);

        circuit_breaker::record_outflow(&mut pool.breaker, amount_out, clock);

        pool.reserve_x.join(bal_in);
        let out_bal = pool.reserve_y.split(amount_out);

        event::emit(SwapExecuted {
            pool_id: pool.id.to_inner(),
            amount_in,
            amount_out,
            fee_taken: fee_amount,
        });

        coin::from_balance(out_bal, ctx)
    }

    public fun claim_queued_whale_withdrawal<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        ticket: &mut QueuedWithdrawalTicket,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<X>, Coin<Y>) {
        let shares = whale_queue::verify_and_consume_ticket(ticket, clock, ctx);
        let total = pool.total_lp_shares as u128;
        assert!(total > 0 && shares > 0, EInsufficientLiquidity);

        let out_x = (((shares as u128) * (pool.reserve_x.value() as u128)) / total) as u64;
        let out_y = (((shares as u128) * (pool.reserve_y.value() as u128)) / total) as u64;
        pool.total_lp_shares = pool.total_lp_shares - shares;

        let bal_x = pool.reserve_x.split(out_x);
        let bal_y = pool.reserve_y.split(out_y);
        (coin::from_balance(bal_x, ctx), coin::from_balance(bal_y, ctx))
    }
}
