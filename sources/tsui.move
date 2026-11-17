module atoadex_core::tsui {
    use sui::coin::{Self, TreasuryCap};

    public struct TSUI has drop {}

    public struct TsuiFaucet has key {
        id: UID,
        cap: TreasuryCap<TSUI>,
    }

    fun init(witness: TSUI, ctx: &mut TxContext) {
        let (cap, metadata) = coin::create_currency(
            witness,
            9,
            b"tSUI",
            b"AtoaDEX Testnet SUI",
            b"Unlimited free Testnet SUI for AtoaDEX testers",
            option::none(),
            ctx
        );
        transfer::public_freeze_object(metadata);
        transfer::share_object(TsuiFaucet {
            id: object::new(ctx),
            cap,
        });
    }

    public entry fun claim_tsui(
        faucet: &mut TsuiFaucet,
        ctx: &mut TxContext
    ) {
        let minted = coin::mint(&mut faucet.cap, 1_000_000_000_000, ctx);
        transfer::public_transfer(minted, ctx.sender());
    }
}

