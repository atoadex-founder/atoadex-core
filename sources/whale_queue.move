/// Module: atoadex_core::whale_queue
/// AtoaDEX v1.9.8 — 24-Hour Timelocked Whale Withdrawal Queue & Same-Address Return Lock
/// Prevents instant single-block drain vectors on large withdrawals (>10.00% pool TVL)
/// and enforces strict Same-Address Return Only (funds can never be redirected to a hacker wallet).
module atoadex_core::whale_queue {
    use sui::clock::Clock;
    use sui::event;
    use atoadex_core::circuit_breaker::SecurityCouncilCap;

    // === Error Codes ===
    const ETimelockNotExpired: u64 = 2001;
    const EUnauthorizedClaimant: u64 = 2002;
    const ETicketAlreadyExecutedOrCancelled: u64 = 2003;
    const EInvalidAmount: u64 = 2004;

    // === Constants ===
    /// 24 hours in milliseconds (24 * 60 * 60 * 1000 = 86,400,000 ms)
    const TWENTY_FOUR_HOURS_MS: u64 = 86_400_000;

    // === Structs ===

    /// Timelocked withdrawal ticket bound strictly to the original depositor address
    public struct QueuedWithdrawalTicket has key, store {
        id: UID,
        pool_id: ID,
        /// Strict Same-Address Return Lock: only this exact address can ever receive the funds
        original_depositor: address,
        lp_shares_locked: u64,
        queued_at_ms: u64,
        unlock_at_ms: u64,
        is_executed: bool,
        is_cancelled: bool,
    }

    // === Events ===

    public struct WhaleWithdrawalQueued has copy, drop {
        ticket_id: ID,
        pool_id: ID,
        original_depositor: address,
        lp_shares_locked: u64,
        unlock_at_ms: u64,
    }

    public struct WhaleWithdrawalExecuted has copy, drop {
        ticket_id: ID,
        pool_id: ID,
        recipient: address,
        lp_shares_released: u64,
    }

    public struct CompromisedTicketCancelled has copy, drop {
        ticket_id: ID,
        pool_id: ID,
        original_depositor: address,
    }

    // === Public Functions ===

    /// Queue a large withdrawal (>10.00% epoch cap) with a mandatory 24-hour timelock
    public fun queue_large_withdrawal(
        pool_id: ID,
        lp_shares_locked: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(lp_shares_locked > 0, EInvalidAmount);

        let now_ms = clock.timestamp_ms();
        let unlock_ms = now_ms + TWENTY_FOUR_HOURS_MS;
        let depositor = ctx.sender();

        let ticket = QueuedWithdrawalTicket {
            id: object::new(ctx),
            pool_id,
            original_depositor: depositor,
            lp_shares_locked,
            queued_at_ms: now_ms,
            unlock_at_ms: unlock_ms,
            is_executed: false,
            is_cancelled: false,
        };

        event::emit(WhaleWithdrawalQueued {
            ticket_id: object::id(&ticket),
            pool_id,
            original_depositor: depositor,
            lp_shares_locked,
            unlock_at_ms: unlock_ms,
        });

        // Transfer ticket directly to the original depositor
        transfer::transfer(ticket, depositor);
    }

    /// Claim the queued withdrawal after 24 hours have elapsed.
    /// Enforces Same-Address Return Only: caller must match original_depositor.
    public fun verify_and_consume_ticket(
        ticket: &mut QueuedWithdrawalTicket,
        clock: &Clock,
        ctx: &TxContext
    ): u64 {
        assert!(!ticket.is_executed && !ticket.is_cancelled, ETicketAlreadyExecutedOrCancelled);
        assert!(ctx.sender() == ticket.original_depositor, EUnauthorizedClaimant);
        assert!(clock.timestamp_ms() >= ticket.unlock_at_ms, ETimelockNotExpired);

        ticket.is_executed = true;

        event::emit(WhaleWithdrawalExecuted {
            ticket_id: object::id(ticket),
            pool_id: ticket.pool_id,
            recipient: ticket.original_depositor,
            lp_shares_released: ticket.lp_shares_locked,
        });

        ticket.lp_shares_locked
    }

    /// Emergency cancellation by the 3-of-5 Security Council if the whale reports
    /// their personal wallet was phished/compromised during the 24-hour window.
    public entry fun council_cancel_compromised_ticket(
        _cap: &SecurityCouncilCap,
        ticket: &mut QueuedWithdrawalTicket
    ) {
        assert!(!ticket.is_executed && !ticket.is_cancelled, ETicketAlreadyExecutedOrCancelled);
        ticket.is_cancelled = true;

        event::emit(CompromisedTicketCancelled {
            ticket_id: object::id(ticket),
            pool_id: ticket.pool_id,
            original_depositor: ticket.original_depositor,
        });
    }
}

