/// Module: atoadex_core::ratoa_vault
/// AtoaDEX v1.9.8 — Self-Healing 1:1 rATOA Perpetual Insurance Vault
/// Pre-seeded on Day 1 with 2,500,000 $ATOA ($400,000 at IDO price) plus a
/// permanent 5.00% swap-fee stream. Automatically replenishes back to the
/// 2,500,000 $ATOA floor via open-market buybacks whenever drawn.
module atoadex_core::ratoa_vault {
    use sui::balance::Balance;
    use sui::coin::{Self, Coin};
    use sui::event;
    use atoadex_core::circuit_breaker::SecurityCouncilCap;

    // === Error Codes ===
    const EInsufficientVaultReserve: u64 = 3001;
    const EInvalidAmount: u64 = 3002;
    const EBelowPerpetualFloor: u64 = 3003;

    // === Constants ===
    /// Canonical Day-1 Perpetual Insurance Floor: 2,500,000 $ATOA (with 9 decimals)
    const PERPETUAL_FLOOR_ATOA: u64 = 2_500_000_000_000_000;

    // === Structs ===

    /// Shared Perpetual Insurance Vault holding $ATOA reserves
    public struct RatoaInsuranceVault<phantom ATOA> has key {
        id: UID,
        reserve_balance: Balance<ATOA>,
        perpetual_floor: u64,
        total_claims_paid: u64,
        total_replenished: u64,
    }

    // === Events ===

    public struct VaultSeededOrReplenished has copy, drop {
        amount_added: u64,
        new_reserve_balance: u64,
        is_floor_restored: bool,
    }

    public struct VerifiedExploitClaimPaid has copy, drop {
        recipient: address,
        amount_paid: u64,
        remaining_reserve: u64,
        deficit_to_heal: u64,
    }

    public struct SurplusRoutedToBuybackBurn has copy, drop {
        surplus_amount: u64,
        remaining_floor_balance: u64,
    }

    // === Public Functions ===

    /// Initialize and pre-seed the rATOA Insurance Vault on Day 1 (2,500,000 $ATOA)
    public fun create_and_seed_vault<ATOA>(
        initial_seed: Coin<ATOA>,
        ctx: &mut TxContext
    ) {
        let amount = initial_seed.value();
        assert!(amount > 0, EInvalidAmount);

        let vault = RatoaInsuranceVault<ATOA> {
            id: object::new(ctx),
            reserve_balance: initial_seed.into_balance(),
            perpetual_floor: PERPETUAL_FLOOR_ATOA,
            total_claims_paid: 0,
            total_replenished: 0,
        };

        event::emit(VaultSeededOrReplenished {
            amount_added: amount,
            new_reserve_balance: amount,
            is_floor_restored: amount >= PERPETUAL_FLOOR_ATOA,
        });

        transfer::share_object(vault);
    }

    /// Deposit permanent 5.00% swap-fee stream or Self-Healing 19% buyback replenishment
    public fun deposit_insurance_stream<ATOA>(
        vault: &mut RatoaInsuranceVault<ATOA>,
        inflow: Coin<ATOA>
    ) {
        let added = inflow.value();
        assert!(added > 0, EInvalidAmount);

        vault.reserve_balance.join(inflow.into_balance());
        vault.total_replenished = vault.total_replenished + added;

        let current = vault.reserve_balance.value();
        event::emit(VaultSeededOrReplenished {
            amount_added: added,
            new_reserve_balance: current,
            is_floor_restored: current >= vault.perpetual_floor,
        });
    }

    /// View helper: Returns true if the vault is currently below the 2,500,000 $ATOA floor
    public fun needs_self_healing<ATOA>(vault: &RatoaInsuranceVault<ATOA>): bool {
        vault.reserve_balance.value() < vault.perpetual_floor
    }

    /// View helper: Returns exact deficit needed to heal back to 2,500,000 $ATOA
    public fun healing_deficit<ATOA>(vault: &RatoaInsuranceVault<ATOA>): u64 {
        let current = vault.reserve_balance.value();
        if (current >= vault.perpetual_floor) {
            0
        } else {
            vault.perpetual_floor - current
        }
    }

    /// Pay out verified exploit compensation to affected LPs (3-of-5 Security Council)
    public entry fun payout_verified_claim<ATOA>(
        _cap: &SecurityCouncilCap,
        vault: &mut RatoaInsuranceVault<ATOA>,
        claim_amount: u64,
        affected_lp: address,
        ctx: &mut TxContext
    ) {
        assert!(claim_amount > 0, EInvalidAmount);
        assert!(vault.reserve_balance.value() >= claim_amount, EInsufficientVaultReserve);

        let payout_bal = vault.reserve_balance.split(claim_amount);
        let payout_coin = coin::from_balance(payout_bal, ctx);
        vault.total_claims_paid = vault.total_claims_paid + claim_amount;

        let remaining = vault.reserve_balance.value();
        let deficit = if (remaining < vault.perpetual_floor) {
            vault.perpetual_floor - remaining
        } else {
            0
        };

        event::emit(VerifiedExploitClaimPaid {
            recipient: affected_lp,
            amount_paid: claim_amount,
            remaining_reserve: remaining,
            deficit_to_heal: deficit,
        });

        transfer::public_transfer(payout_coin, affected_lp);
    }

    /// Immortal Reserve Overflow: Only surplus strictly above the 2,500,000 $ATOA floor
    /// can ever be routed to open-market buyback-and-burn (0x0).
    public fun withdraw_surplus_for_burn<ATOA>(
        _cap: &SecurityCouncilCap,
        vault: &mut RatoaInsuranceVault<ATOA>,
        surplus_amount: u64,
        ctx: &mut TxContext
    ): Coin<ATOA> {
        let current = vault.reserve_balance.value();
        assert!(current > vault.perpetual_floor, EBelowPerpetualFloor);
        assert!(current - surplus_amount >= vault.perpetual_floor, EBelowPerpetualFloor);

        let burn_bal = vault.reserve_balance.split(surplus_amount);
        event::emit(SurplusRoutedToBuybackBurn {
            surplus_amount,
            remaining_floor_balance: vault.reserve_balance.value(),
        });

        coin::from_balance(burn_bal, ctx)
    }
}
