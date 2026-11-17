module atoadex::genesis_atoa {
    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object::{Self, UID};

    public struct GENESIS_ATOA has drop {}

    // Exact v1.9.8 Canonical Allocations (9 decimals)
    const LOCKED_POL_ALLOC: u64 = 70_000_000 * 1_000_000_000;      // 70.00%
    const PUBLIC_IDO_ALLOC: u64 = 15_000_000 * 1_000_000_000;      // 15.00%
    const ECOSYSTEM_ALLOC: u64 = 8_000_000 * 1_000_000_000;        // 8.00%
    const FOUNDER_VEST_ALLOC: u64 = 4_500_000 * 1_000_000_000;     // 4.50%
    const RATOA_INSURANCE_ALLOC: u64 = 2_500_000 * 1_000_000_000;  // 2.50%

    public struct GenesisVaults has key {
        id: UID,
        locked_pol: Coin<GENESIS_ATOA>,
        public_ido: Coin<GENESIS_ATOA>,
        ecosystem_pool: Coin<GENESIS_ATOA>,
        ratoa_insurance_seed: Coin<GENESIS_ATOA>,
    }

    // Founder 4-Year Vesting Vault with active veATOA voting & weekly bribe eligibility
    public struct FounderVestingVeVault has key, store {
        id: UID,
        vesting_balance: Coin<GENESIS_ATOA>,
        active_ve_voting_power: u64,
        bribe_rewards_eligible: bool,
        cliff_months: u64,
        vesting_months: u64,
    }

    fun init(witness: GENESIS_ATOA, ctx: &mut TxContext) {
        let (mut treasury_cap, metadata) = coin::create_currency(
            witness,
            9,
            b"ATOA",
            b"AtoaDEX Governance & Real-Yield Token",
            b"Canonical 100M Supply - Insured & Circuit-Broken Sui DEX",
            option::none(),
            ctx
        );
        transfer::public_freeze_object(metadata);

        let locked_pol = coin::mint(&mut treasury_cap, LOCKED_POL_ALLOC, ctx);
        let public_ido = coin::mint(&mut treasury_cap, PUBLIC_IDO_ALLOC, ctx);
        let ecosystem_pool = coin::mint(&mut treasury_cap, ECOSYSTEM_ALLOC, ctx);
        let founder_vesting = coin::mint(&mut treasury_cap, FOUNDER_VEST_ALLOC, ctx);
        let ratoa_insurance_seed = coin::mint(&mut treasury_cap, RATOA_INSURANCE_ALLOC, ctx);

        // Permanently freeze supply at 100,000,000 $ATOA
        transfer::public_freeze_object(treasury_cap);

        transfer::share_object(GenesisVaults {
            id: object::new(ctx),
            locked_pol,
            public_ido,
            ecosystem_pool,
            ratoa_insurance_seed,
        });

        // Transfer Founder Vesting + Active veATOA Bribe Vault to deployer
        transfer::public_transfer(FounderVestingVeVault {
            id: object::new(ctx),
            vesting_balance: founder_vesting,
            active_ve_voting_power: FOUNDER_VEST_ALLOC,
            bribe_rewards_eligible: true,
            cliff_months: 12,
            vesting_months: 48,
        }, tx_context::sender(ctx));
    }
}
