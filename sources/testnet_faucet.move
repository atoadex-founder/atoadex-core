module atoadex::testnet_faucet {
    use sui::coin::{Self, TreasuryCap};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object::{Self, UID};

    // 3 Testnet Stablecoins
    public struct TUSDC has drop {}
    public struct TUSDY has drop {}
    public struct TAUSD has drop {}

    // 4-Throne Testnet LSTs
    public struct THASUI has drop {}
    public struct TVSUI has drop {}
    public struct TSSUI has drop {}
    public struct TAFSUI has drop {}

    public struct FaucetCap has key {
        id: UID,
        usdc_cap: TreasuryCap<TUSDC>,
        usdy_cap: TreasuryCap<TUSDY>,
        ausd_cap: TreasuryCap<TAUSD>,
        hasui_cap: TreasuryCap<THASUI>,
        vsui_cap: TreasuryCap<TVSUI>,
        ssui_cap: TreasuryCap<TSSUI>,
        afsui_cap: TreasuryCap<TAFSUI>,
    }

    fun init(ctx: &mut TxContext) {
        let (usdc_cap, m1) = coin::create_currency(TUSDC {}, 6, b"tUSDC", b"AtoaDEX Testnet USDC", b"Testnet Stablecoin", option::none(), ctx);
        let (usdy_cap, m2) = coin::create_currency(TUSDY {}, 6, b"tUSDY", b"AtoaDEX Testnet USDY", b"Testnet Yield Stablecoin", option::none(), ctx);
        let (ausd_cap, m3) = coin::create_currency(TAUSD {}, 6, b"tAUSD", b"AtoaDEX Testnet AUSD", b"Testnet Agora USD", option::none(), ctx);
        let (hasui_cap, m4) = coin::create_currency(THASUI {}, 9, b"thaSUI", b"AtoaDEX Testnet haSUI", b"Testnet Haedal LST", option::none(), ctx);
        let (vsui_cap, m5) = coin::create_currency(TVSUI {}, 9, b"tvSUI", b"AtoaDEX Testnet vSUI", b"Testnet Volo LST", option::none(), ctx);
        let (ssui_cap, m6) = coin::create_currency(TSSUI {}, 9, b"tsSUI", b"AtoaDEX Testnet sSUI", b"Testnet SpringSui LST", option::none(), ctx);
        let (afsui_cap, m7) = coin::create_currency(TAFSUI {}, 9, b"tafSUI", b"AtoaDEX Testnet afSUI", b"Testnet Aftermath LST", option::none(), ctx);

        transfer::public_freeze_object(m1);
        transfer::public_freeze_object(m2);
        transfer::public_freeze_object(m3);
        transfer::public_freeze_object(m4);
        transfer::public_freeze_object(m5);
        transfer::public_freeze_object(m6);
        transfer::public_freeze_object(m7);

        transfer::share_object(FaucetCap {
            id: object::new(ctx),
            usdc_cap, usdy_cap, ausd_cap,
            hasui_cap, vsui_cap, ssui_cap, afsui_cap,
        });
    }

    public entry fun mint_stable_pack(faucet: &mut FaucetCap, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        transfer::public_transfer(coin::mint(&mut faucet.usdc_cap, 1_000_000_000, ctx), sender);
        transfer::public_transfer(coin::mint(&mut faucet.usdy_cap, 1_000_000_000, ctx), sender);
        transfer::public_transfer(coin::mint(&mut faucet.ausd_cap, 1_000_000_000, ctx), sender);
    }

    public entry fun mint_lst_pack(faucet: &mut FaucetCap, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        transfer::public_transfer(coin::mint(&mut faucet.hasui_cap, 100_000_000_000, ctx), sender);
        transfer::public_transfer(coin::mint(&mut faucet.vsui_cap, 100_000_000_000, ctx), sender);
        transfer::public_transfer(coin::mint(&mut faucet.ssui_cap, 100_000_000_000, ctx), sender);
        transfer::public_transfer(coin::mint(&mut faucet.afsui_cap, 100_000_000_000, ctx), sender);
    }
}
