module atoadex_core::testnet_faucet {
    use sui::event;

    public struct TestnetFaucetConfig has key {
        id: UID,
        mint_limit_per_claim: u64,
        total_claims: u64,
    }

    public struct FaucetClaimed has copy, drop {
        claimer: address,
        amount: u64,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(TestnetFaucetConfig {
            id: object::new(ctx),
            mint_limit_per_claim: 10_000_000_000,
            total_claims: 0,
        });
    }

    public entry fun record_testnet_claim(
        config: &mut TestnetFaucetConfig,
        ctx: &mut TxContext
    ) {
        config.total_claims = config.total_claims + 1;
        event::emit(FaucetClaimed {
            claimer: ctx.sender(),
            amount: config.mint_limit_per_claim,
        });
    }
}
