module atoadex_core::atoa {
    use sui::coin::{Self, Coin};
    use sui::url;

    const MAX_SUPPLY_RAW: u64 = 100_000_000_000_000_000; // 100M * 10^9
    const GENESIS_POL_RAW: u64 = 70_000_000_000_000_000;  // 70.00%
    const PUBLIC_IDO_RAW: u64 = 15_000_000_000_000_000;   // 15.00%
    const ECOSYSTEM_RAW: u64 = 8_000_000_000_000_000;     // 8.00%
    const RATOA_INSURANCE_RAW: u64 = 2_500_000_000_000_000; // 2.50%
    const FOUNDER_VESTING_RAW: u64 = 4_500_000_000_000_000; // 4.50%

    public struct ATOA has drop {}

    public struct GenesisVaults has key {
        id: UID,
        locked_pol: Coin<ATOA>,
        public_ido: Coin<ATOA>,
        ecosystem_pool: Coin<ATOA>,
        ratoa_insurance_seed: Coin<ATOA>,
    }

    public struct FounderVestingVault has key {
        id: UID,
        beneficiary: address,
        vesting_balance: Coin<ATOA>,
    }

    fun init(witness: ATOA, ctx: &mut TxContext) {
        let (mut treasury_cap, metadata) = coin::create_currency(
            witness,
            9,
            b"ATOA",
            b"AtoaDEX Governance & Utility Token",
            b"Canonical v1.9.8 Self-Healing Hybrid DEX on Sui Network",
                        option::none(),

            ctx
        );
        transfer::public_freeze_object(metadata);

        let locked_pol = coin::mint(&mut treasury_cap, GENESIS_POL_RAW, ctx);
        let public_ido = coin::mint(&mut treasury_cap, PUBLIC_IDO_RAW, ctx);
        let ecosystem_pool = coin::mint(&mut treasury_cap, ECOSYSTEM_RAW, ctx);
        let ratoa_insurance_seed = coin::mint(&mut treasury_cap, RATOA_INSURANCE_RAW, ctx);
        let vesting_balance = coin::mint(&mut treasury_cap, FOUNDER_VESTING_RAW, ctx);

        assert!(
            GENESIS_POL_RAW + PUBLIC_IDO_RAW + ECOSYSTEM_RAW + RATOA_INSURANCE_RAW + FOUNDER_VESTING_RAW == MAX_SUPPLY_RAW,
            1001
        );

        transfer::public_freeze_object(treasury_cap);

        transfer::share_object(GenesisVaults {
            id: object::new(ctx),
            locked_pol,
            public_ido,
            ecosystem_pool,
            ratoa_insurance_seed,
        });

        transfer::share_object(FounderVestingVault {
            id: object::new(ctx),
            beneficiary: ctx.sender(),
            vesting_balance,
        });
    }
}
