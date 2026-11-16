/// Module: atoadex_core::circuit_breaker
/// AtoaDEX v1.9.8 — 2-Tier Per-Epoch Pool Outflow Circuit Breaker
/// Enforces a hardcoded 10.00% (1,000 bps) per-epoch outflow limit per pool
/// and triggers a Global DEX Pause if >= 2 pools breach within the same epoch.
module atoadex_core::circuit_breaker {
    use sui::event;

    // === Error Codes ===
    const EGlobalDexPaused: u64 = 1001;
    const EPoolFrozenByCircuitBreaker: u64 = 1002;

    // === Constants ===
    /// Hardcoded 10.00% (1,000 basis points) max outflow per epoch per pool
    const MAX_EPOCH_OUTFLOW_BPS: u64 = 1000;
    const BPS_DENOMINATOR: u64 = 10000;
    /// If >= 2 pools breach in the same epoch, freeze the entire DEX router
    const GLOBAL_FREEZE_POOL_THRESHOLD: u64 = 2;

    // === Structs ===

    /// Capability held by the 3-of-5 Security Council Multisig for emergency unfreeze
    public struct SecurityCouncilCap has key, store {
        id: UID,
    }

    /// Global shared state tracking protocol-wide pause and current epoch breaches
    public struct GlobalBreakerRegistry has key {
        id: UID,
        is_global_paused: bool,
        current_epoch: u64,
        breached_pools_in_epoch: u64,
    }

    /// Per-pool outflow tracker attached to each AtoaDEX liquidity pool
    public struct PoolCircuitBreaker has key, store {
        id: UID,
        pool_id: ID,
        is_pool_frozen: bool,
        tracked_epoch: u64,
        epoch_start_tvl: u64,
        epoch_cumulative_outflow: u64,
    }

    // === Events ===

    public struct PoolBreakerTriggered has copy, drop {
        pool_id: ID,
        epoch: u64,
        epoch_start_tvl: u64,
        attempted_outflow: u64,
    }

    public struct GlobalBreakerTriggered has copy, drop {
        epoch: u64,
        breached_pools_count: u64,
    }

    public struct PoolUnfrozen has copy, drop {
        pool_id: ID,
        epoch: u64,
    }

    // === Initialization ===

    fun init(ctx: &mut TxContext) {
        let registry = GlobalBreakerRegistry {
            id: object::new(ctx),
            is_global_paused: false,
            current_epoch: ctx.epoch(),
            breached_pools_in_epoch: 0,
        };
        transfer::share_object(registry);

        let admin_cap = SecurityCouncilCap {
            id: object::new(ctx),
        };
        transfer::transfer(admin_cap, ctx.sender());
    }

    // === Public Functions ===

    /// Create a new PoolCircuitBreaker when a new pool is deployed
    public fun create_pool_breaker(
        pool_id: ID,
        initial_tvl: u64,
        ctx: &mut TxContext
    ): PoolCircuitBreaker {
        PoolCircuitBreaker {
            id: object::new(ctx),
            pool_id,
            is_pool_frozen: false,
            tracked_epoch: ctx.epoch(),
            epoch_start_tvl: initial_tvl,
            epoch_cumulative_outflow: 0,
        }
    }

    /// Update baseline TVL when legitimate deposits enter the pool
    public fun record_inflow(
        breaker: &mut PoolCircuitBreaker,
        inflow_amount: u64,
        ctx: &TxContext
    ) {
        sync_epoch_if_needed(breaker, ctx);
        breaker.epoch_start_tvl = breaker.epoch_start_tvl + inflow_amount;
    }

    /// Core Security Check: Validates every withdrawal against the 10.00% epoch cap.
    /// Returns true if allowed; freezes pool (and global DEX if >=2 pools) if breached.
    public fun check_and_record_outflow(
        registry: &mut GlobalBreakerRegistry,
        breaker: &mut PoolCircuitBreaker,
        outflow_amount: u64,
        current_pool_tvl: u64,
        ctx: &TxContext
    ): bool {
        let now_epoch = ctx.epoch();

        if (registry.current_epoch < now_epoch) {
            registry.current_epoch = now_epoch;
            registry.breached_pools_in_epoch = 0;
        };

        assert!(!registry.is_global_paused, EGlobalDexPaused);

        // Automatic Next-Epoch Reset
        if (breaker.tracked_epoch < now_epoch) {
            breaker.tracked_epoch = now_epoch;
            breaker.epoch_start_tvl = current_pool_tvl;
            breaker.epoch_cumulative_outflow = 0;
            breaker.is_pool_frozen = false;
        };

        assert!(!breaker.is_pool_frozen, EPoolFrozenByCircuitBreaker);

        let max_allowed = ((breaker.epoch_start_tvl as u128) * (MAX_EPOCH_OUTFLOW_BPS as u128)
            / (BPS_DENOMINATOR as u128)) as u64;
        let new_cumulative = breaker.epoch_cumulative_outflow + outflow_amount;

        if (new_cumulative > max_allowed && breaker.epoch_start_tvl > 0) {
            breaker.is_pool_frozen = true;
            registry.breached_pools_in_epoch = registry.breached_pools_in_epoch + 1;

            event::emit(PoolBreakerTriggered {
                pool_id: breaker.pool_id,
                epoch: now_epoch,
                epoch_start_tvl: breaker.epoch_start_tvl,
                attempted_outflow: new_cumulative,
            });

            if (registry.breached_pools_in_epoch >= GLOBAL_FREEZE_POOL_THRESHOLD) {
                registry.is_global_paused = true;
                event::emit(GlobalBreakerTriggered {
                    epoch: now_epoch,
                    breached_pools_count: registry.breached_pools_in_epoch,
                });
            };

            return false
        };

        breaker.epoch_cumulative_outflow = new_cumulative;
        true
    }

    /// Emergency unfreeze by the 3-of-5 Security Council after on-chain verification
    public entry fun council_unfreeze_pool(
        _cap: &SecurityCouncilCap,
        registry: &mut GlobalBreakerRegistry,
        breaker: &mut PoolCircuitBreaker,
        verified_tvl: u64,
        ctx: &TxContext
    ) {
        let now_epoch = ctx.epoch();
        breaker.is_pool_frozen = false;
        breaker.tracked_epoch = now_epoch;
        breaker.epoch_start_tvl = verified_tvl;
        breaker.epoch_cumulative_outflow = 0;
        registry.is_global_paused = false;

        event::emit(PoolUnfrozen {
            pool_id: breaker.pool_id,
            epoch: now_epoch,
        });
    }

    // === Internal Helpers ===

    fun sync_epoch_if_needed(breaker: &mut PoolCircuitBreaker, ctx: &TxContext) {
        let now_epoch = ctx.epoch();
        if (breaker.tracked_epoch < now_epoch) {
            breaker.tracked_epoch = now_epoch;
            breaker.epoch_cumulative_outflow = 0;
            breaker.is_pool_frozen = false;
        };
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
