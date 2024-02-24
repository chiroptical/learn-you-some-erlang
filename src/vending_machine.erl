-module(vending_machine).
-behaviour(gen_statem).

-export([
    start_link/1,
    flip_switch/1,
    request_coins/1,
    request_soda/1,
    insert_coin/2
]).

%% Mandatory callbacks
-export([
    init/1,
    callback_mode/0,
    terminate/3,
    code_change/4,
    on/3,
    off/3
]).

%% For testing
-export([
    add_coin/2,
    add_coins/2,
    optimize_coins/3,
    make_change/3
]).

-type coin() :: nickel | dime | quarter.

-define(COST_OF_SODA, 150).

-record(state, {
    inserted_coins = maps:new() :: maps:iterator(coin(), pos_integer()),
    bank = maps:new() :: maps:iterator(coin(), pos_integer())
}).

%% I don't know why this doesn't work...
%% -spec start_link(maps:iterator(coin(), pos_integer())) -> gen_statem:start_ret().
start_link(Bank) ->
    gen_statem:start_link(?MODULE, [], [Bank]).

init([Bank]) ->
    {ok, off, #state{inserted_coins = map:new(), bank = Bank}}.

flip_switch(Pid) ->
    gen_statem:call(Pid, flip_switch).

request_coins(Pid) ->
    gen_statem:call(Pid, request_coins).

request_soda(Pid) ->
    gen_statem:call(Pid, request_soda).

-spec insert_coin(pid(), coin()) -> any().
insert_coin(Pid, Coin) ->
    gen_statem:call(Pid, {insert_coin, Coin}).

on({call, From}, flip_switch, S = #state{}) ->
    {next_state, off, S#state{inserted_coins = map:new()}, [
        {reply, From, S#state.inserted_coins}
    ]};
on({call, From}, request_coins, S = #state{}) ->
    {next_state, on, S#state{inserted_coins = map:new()}, [
        {reply, From, S#state.inserted_coins}
    ]};
%% TODO: Finish this
on({call, From}, request_soda, S = #state{}) ->
    {next_state, on, S, [
        {reply, From, []}
    ]};
on({call, From}, {insert_coin, Coin}, S = #state{inserted_coins = Coins}) ->
    {ok, CoinsToReturn, Optimized} = optimize_coins(
        ?COST_OF_SODA, add_coin(Coin, Coins), map:empty()
    ),
    {next_state, on,
        S#state{
            inserted_coins = Optimized
        },
        [
            {reply, From, {insert, {coin, Coin}, {returned, CoinsToReturn}}}
        ]}.

off({call, From}, flip_switch, S = #state{}) ->
    {next_state, on, S, [
        {reply, From, on}
    ]};
off({call, From}, request_coins, S = #state{}) ->
    {next_state, on, S, [
        {reply, From, machine_off}
    ]};
off({call, From}, request_soda, S = #state{}) ->
    {next_state, on, S, [
        {reply, From, machine_off}
    ]};
off({call, From}, {insert_coin, Coin}, S = #state{}) ->
    {next_state, on, S, [
        {reply, From, {machine_off, Coin}}
    ]}.

%% Mandatory callbacks

terminate(_Reason, _State, _Data) ->
    void.

code_change(_Version, State, Data, _Extra) ->
    {ok, State, Data}.

callback_mode() ->
    state_functions.

%% module helpers

add_coin(Coin, Coins) ->
    maps:update_with(Coin, fun(Count) -> Count + 1 end, 1, Coins).

add_coins(Coins, Bank) ->
    maps:merge_with(fun(_Key, X, Y) -> X + Y end, Coins, Bank).

%% Given a cost, coins in the machine, and bank, attempt to make change for the
%% customer. If we are unable, return an error for now. We may ask the user to
%% press the button to confirm we can move forward without providing change. We
%% can also let the customer know when they interact with the machine without
%% any nickels we can't make change.
make_change(Cost, Coins, Bank) ->
    CoinValue = coins_value(Coins),
    case CoinValue >= Cost of
        true ->
            CustomerExpects = CoinValue - Cost,
            {ok, NextBank, Change} = optimize_coins(
                CustomerExpects, add_coins(Coins, Bank), maps:new()
            ),
            ChangeValue = coins_value(Change),
            io:format("CustomerExpects ~p; ChangeValue: ~p~n", [CustomerExpects, ChangeValue]),
            case ChangeValue == CustomerExpects of
                false -> unable_to_make_change;
                true -> {ok, Change, NextBank}
            end;
        false ->
            unable_to_cover_cost
    end.

%% Given a limit, e.g. 150 cents, get as close to that as we possibly can
%% without going over.
optimize_coins(Limit, Coins, Optimized) when Limit =< 0 ->
    {ok, Coins, Optimized};
optimize_coins(Limit, Coins, Optimized) when Limit =< 5 ->
    case select_smallest_possible_coin(Coins) of
        {Coin, NewCoins} ->
            {ok, NewCoins, add_coin(Coin, Optimized)};
        empty ->
            {ok, Coins, Optimized}
    end;
optimize_coins(Limit, Coins, Optimized) ->
    case select_largest_possible_coin(Limit, Coins) of
        {Coin, NewCoins} -> recurse_optimize(Coin, Limit, NewCoins, Optimized);
        empty -> {ok, Coins, Optimized}
    end.

recurse_optimize(Coin, Limit, Coins, Optimized) ->
    optimize_coins(Limit - coin_value(Coin), Coins, add_coin(Coin, Optimized)).

subtract_coin(Coin, Coins) ->
    case maps:get(Coin, Coins, 0) of
        0 -> empty;
        1 -> {Coin, maps:remove(Coin, Coins)};
        X -> {Coin, maps:update(Coin, X - 1, Coins)}
    end.

select_largest_possible_coin(Limit, Coins) ->
    Quarters = maps:get(quarter, Coins, 0),
    Dimes = maps:get(dime, Coins, 0),
    Nickels = maps:get(nickel, Coins, 0),
    case {Quarters, Dimes, Nickels} of
        {X, _, _} when X > 0, Limit > 10 -> subtract_coin(quarter, Coins);
        {_, X, _} when X > 0, Limit > 5 -> subtract_coin(dime, Coins);
        {_, _, X} when X > 0 -> subtract_coin(nickel, Coins);
        _ -> empty
    end.

select_smallest_possible_coin(Coins) ->
    Quarters = maps:get(quarter, Coins, 0),
    Dimes = maps:get(dime, Coins, 0),
    Nickels = maps:get(nickel, Coins, 0),
    case {Quarters, Dimes, Nickels} of
        {_, _, X} when X > 0 -> subtract_coin(nickel, Coins);
        {_, X, _} when X > 0 -> subtract_coin(dime, Coins);
        {X, _, _} when X > 0 -> subtract_coin(quarter, Coins);
        _ -> empty
    end.

coin_value(Coin) ->
    case Coin of
        nickel -> 5;
        dime -> 10;
        quarter -> 25
    end.

coins_value(Coins) ->
    maps:fold(
        fun(Key, Value, Acc) -> coin_value(Key) * Value + Acc end,
        0,
        Coins
    ).
