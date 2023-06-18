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

-export([
    add_coin/2,
    optimize_coins/3
]).

-type coin() :: nickel | dime | quarter.

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
    case coins_value(Coins) >= 150 of
        true ->
            {next_state, on, S, [
                {reply, From, {no_insert, Coin}}
            ]};
        false ->
            %% TODO: Ideally we minimize the overall value
            {next_state, on,
                S#state{
                    inserted_coins =
                        maps:update_with(Coin, fun(Count) -> Count + 1 end, 1, Coins)
                },
                [
                    {reply, From, {inserted, Coin}}
                ]}
    end.

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

recurse_optimize(Coin, Limit, Coins, Optimized) ->
    optimize_coins(Limit - coin_value(Coin), Coins, add_coin(Coin, Optimized)).

%% Given a limit, e.g. 150 cents, get as close to that as we possibly can
%% without going over.
optimize_coins(Limit, Coins, Optimized) when Limit == 0 ->
    io:format("Limit is zero, optimized"),
    {optimized, Coins, Optimized};
optimize_coins(Limit, Coins, Optimized) when Limit =< 5 ->
    case select_smallest_possible_coin(Coins) of
        {Coin, NewCoins} ->
            {optimized, NewCoins, add_coin(Coin, Optimized)};
        empty ->
            {optimized, Coins, Optimized}
    end;
optimize_coins(Limit, Coins, Optimized) ->
    case select_largest_possible_coin(Limit, Coins) of
        {Coin, NewCoins} -> recurse_optimize(Coin, Limit, NewCoins, Optimized);
        empty -> {optimized, Coins, Optimized}
    end.

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
        {X, _, _} when X > 0, Limit >= 25 -> subtract_coin(quarter, Coins);
        {_, X, _} when X > 0, Limit >= 10 -> subtract_coin(dime, Coins);
        {_, _, X} when X > 0, Limit >= 5 -> subtract_coin(nickel, Coins);
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
