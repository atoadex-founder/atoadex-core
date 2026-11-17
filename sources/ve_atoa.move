module atoadex::ve_atoa {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::event;

    const MAX_LOCK_MS: u64 = 126_144_000_000; // 4 years in ms
    const EInvalidDuration: u64 = 1;
    const ELockNotExpired: u64 = 2;

    public struct VeAtoaNFT has key, store {
        id: UID,
        locked_amount: u64,
        voting_power: u64,
        unlock_timestamp_ms: u64,
    }

    public struct LockCreated has copy, drop {
        nft_id: ID,
        owner: address,
        locked_amount: u64,
        voting_power: u64,
        unlock_timestamp_ms: u64,
    }

    public entry fun create_lock(
        amount: u64,
        duration_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(duration_ms > 0 && duration_ms <= MAX_LOCK_MS, EInvalidDuration);
        let now = clock::timestamp_ms(clock);
        let unlock_ts = now + duration_ms;
        let power = ((amount as u128) * (duration_ms as u128) / (MAX_LOCK_MS as u128)) as u64;

        let nft = VeAtoaNFT {
            id: object::new(ctx),
            locked_amount: amount,
            voting_power: power,
            unlock_timestamp_ms: unlock_ts,
        };
        let nft_id = object::id(&nft);
        let sender = tx_context::sender(ctx);

        event::emit(LockCreated {
            nft_id,
            owner: sender,
            locked_amount: amount,
            voting_power: power,
            unlock_timestamp_ms: unlock_ts,
        });

        transfer::public_transfer(nft, sender);
    }

    public entry fun burn_expired_lock(nft: VeAtoaNFT, clock: &Clock) {
        let now = clock::timestamp_ms(clock);
        assert!(now >= nft.unlock_timestamp_ms, ELockNotExpired);
        let VeAtoaNFT { id, locked_amount: _, voting_power: _, unlock_timestamp_ms: _ } = nft;
        object::delete(id);
    }
}
