use ekubo::interfaces::core::{ICoreDispatcherTrait, ICoreDispatcher, IExtensionDispatcher};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::types::keys::{PoolKey};
use ekubo::types::bounds::{Bounds};
use ekubo::types::i129::{i129};
use core::num::traits::{Zero};
use fairlaunch::interfaces::Irouter::{IRouterDispatcher, IRouterDispatcherTrait, Swap, TokenAmount, RouteNode};
use fairlaunch::tests::test_token::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    declare, DeclareResultTrait, ContractClassTrait, ContractClass, start_cheat_caller_address, stop_cheat_caller_address};
use starknet::{ContractAddress, get_contract_address, contract_address_const};

fn deploy_token(
    class: @ContractClass, recipient: ContractAddress, amount: u256
) -> IERC20Dispatcher {
    let (contract_address, _) = class
        .deploy(@array![recipient.into(), amount.low.into(), amount.high.into()])
        .expect('Deploy token failed');

    IERC20Dispatcher { contract_address }
}

fn router() -> IRouterDispatcher {
    IRouterDispatcher {
        contract_address: contract_address_const::<
            0x0199741822c2dc722f6f605204f35e56dbc23bceed54818168c4c49e4fb8737e
        >()
    }
}

fn ekubo_core() -> ICoreDispatcher {
    ICoreDispatcher {
        contract_address: contract_address_const::<
            0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b
        >()
    }
}

fn positions() -> IPositionsDispatcher {
    IPositionsDispatcher {
        contract_address: contract_address_const::<
            0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067
        >()
    }
}

fn setup() -> PoolKey {
    // Declare contract classes
    let test_token_class = declare("TestToken").unwrap().contract_class();
    
    // Use current contract as owner
    let owner = get_contract_address();
    
    // Deploy tokens to owner (the test contract itself)
    let token0 = deploy_token(test_token_class, owner, 0xffffffffffffffffffffffffffffffff);
    let token1 = deploy_token(test_token_class, owner, 0xffffffffffffffffffffffffffffffff);
    
    // Sort tokens by address (inline implementation)
    let (tokenA, tokenB) = {
        let addr0 = token0.contract_address;
        let addr1 = token1.contract_address;
        if addr0 < addr1 {
            (addr0, addr1)
        } else {
            (addr1, addr0)
        }
    };

    // Create PoolKey
    let pool_key = PoolKey {
        token0: tokenA,
        token1: tokenB,
        fee: 0, // 0% fee
        tick_spacing: 1, // Tick spacing, tick spacing percentage 0.1%
        extension: contract_address_const::<0x0>()
    };

    pool_key
}

#[test]
#[fork("mainnet")]
fn test_single_tick_swap_multiple_accounts() {
    let pool_key = setup();

    ekubo_core().initialize_pool(pool_key, Zero::zero());
    
    // Transfer tokens and mint position (your existing code)
    IERC20Dispatcher{ contract_address: pool_key.token0 }
        .transfer(positions().contract_address, 1_000_000);
    IERC20Dispatcher{ contract_address: pool_key.token1 }
        .transfer(positions().contract_address, 1_000_000);
    // Mint position, deposit tokens and clear anything left
    positions().mint_and_deposit_and_clear_both(
        pool_key,
        Bounds {
            lower: i129 { mag: 10050, sign: true },
            upper: i129 { mag: 0, sign: false }
        },
        0
    );
    
    // Prepare swap parameters
    let amount_in: u128 = 400000;
    let token_amount = TokenAmount {
        token: pool_key.token0,
        amount: i129 { mag: amount_in, sign: false }, // Exact input (positive)
    };

    // Get current pool price
    let pool_price = ekubo_core().get_pool_price(pool_key);
    let current_sqrt_price = pool_price.sqrt_ratio;
    println!("Current sqrt price: {}", current_sqrt_price);

    // Determine trade direction
    let _is_token1 = pool_key.token1 == token_amount.token;
    // -5% 323268248574891540290205877060179800883 'INSUFFICIENT_TF_BALANCE'
    // 0% 340282366920938463463374607431768211456 Success
    // 5% 357296485266985386636543337803356622028 'LIMIT_DIRECTION'
    // 20% 408338840305126156156049528918121853747 'LIMIT_DIRECTION' 
    let sqrt_ratio_limit : u256 = 323268248574891540290205877060179800883;
    println!("Sqrt price limit: {}", sqrt_ratio_limit);

    let route = RouteNode {
        pool_key,
        sqrt_ratio_limit,
        skip_ahead: 0,
    };
    let swap_data = Swap {
        route,
        token_amount,
    };

    let _balance_before = IERC20Dispatcher{ contract_address: pool_key.token0 }
        .balanceOf(get_contract_address());

    //1. Transfer tokens to router to spend
    IERC20Dispatcher{ contract_address: pool_key.token0 }
        .transfer(router().contract_address, amount_in.into());

    // Print balances before swap
    let balance_core1 = IERC20Dispatcher{ contract_address: pool_key.token1 }
        .balanceOf(ekubo_core().contract_address);

    println!("Core balance token1 before swap: {}", balance_core1);

    let balance_core0 = IERC20Dispatcher{ contract_address: pool_key.token0 }
        .balanceOf(ekubo_core().contract_address);

    println!("Core balance token0 before swap: {}", balance_core0);

    let balance_account_before = IERC20Dispatcher{ contract_address: pool_key.token1 }
        .balanceOf(get_contract_address());
    println!("account balance token1 before {}", balance_account_before);

    // Execute the swap
    router().swap(swap_data);

    let _balance_after = IERC20Dispatcher{ contract_address: pool_key.token0 }
        .balanceOf(get_contract_address());


    let balance_core1 = IERC20Dispatcher{ contract_address: pool_key.token1 }
        .balanceOf(ekubo_core().contract_address);

    println!("Core balance token1 after swap: {}", balance_core1);

    let balance_core0 = IERC20Dispatcher{ contract_address: pool_key.token0 }
        .balanceOf(ekubo_core().contract_address);

    println!("Core balance token0 after swap: {}", balance_core0);

    let balance_account_after = IERC20Dispatcher{ contract_address: pool_key.token1 }
        .balanceOf(get_contract_address());
    println!("account balance token1 after {}", balance_account_after);

    ////////////////////////////////////////////////////////////////////
    
    //2. Transfer tokens to router to spend
    IERC20Dispatcher{ contract_address: pool_key.token0 }
        .transfer(router().contract_address, amount_in.into());

    // Print balances before swap
    let balance_core1 = IERC20Dispatcher{ contract_address: pool_key.token1 }
        .balanceOf(ekubo_core().contract_address);

    println!("Core balance token1 before swap2: {}", balance_core1);

    let balance_core0 = IERC20Dispatcher{ contract_address: pool_key.token0 }
        .balanceOf(ekubo_core().contract_address);

    println!("Core balance token0 before swap2: {}", balance_core0);

    let balance_account_before = IERC20Dispatcher{ contract_address: pool_key.token1 }
        .balanceOf(get_contract_address());
    println!("account balance token1 before {}", balance_account_before);

    // Execute the swap
    router().swap(swap_data);

    let _balance_after = IERC20Dispatcher{ contract_address: pool_key.token0 }
        .balanceOf(get_contract_address());


    let balance_core1 = IERC20Dispatcher{ contract_address: pool_key.token1 }
        .balanceOf(ekubo_core().contract_address);

    println!("Core balance token1 after swap2: {}", balance_core1);

    let balance_core0 = IERC20Dispatcher{ contract_address: pool_key.token0 }
        .balanceOf(ekubo_core().contract_address);

    println!("Core balance token0 after swap2: {}", balance_core0);

    let balance_account_after = IERC20Dispatcher{ contract_address: pool_key.token1 }
        .balanceOf(get_contract_address());
    println!("account balance token1 after {}", balance_account_after);

}



