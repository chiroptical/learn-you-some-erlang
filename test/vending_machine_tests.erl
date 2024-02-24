-module(vending_machine_tests).
-include_lib("eunit/include/eunit.hrl").

add_coin_test() ->
    ?assertEqual(vending_machine:add_coin(dime, maps:new()), #{dime => 1}).

optimize_coins_nothing_to_optimize_should_work_test() ->
    {ok, Coins, Optimized} = vending_machine:optimize_coins(100, maps:new(), maps:new()),
    0 = maps:size(Coins),
    0 = maps:size(Optimized).

optimize_coins_remove_quarter_should_work_test() ->
    Coins = #{quarter => 1},
    {ok, NewCoins, Optimized} = vending_machine:optimize_coins(25, Coins, maps:new()),
    0 = maps:size(NewCoins),
    ?assertEqual(Optimized, Coins).

optimize_coins_remove_quarters_should_work_test() ->
    Coins = #{quarter => 4},
    {ok, NewCoins, Optimized} = vending_machine:optimize_coins(100, Coins, maps:new()),
    0 = maps:size(NewCoins),
    ?assertEqual(Optimized, Coins).

optimize_coins_one_fifty_from_quarters_dimes_test() ->
    Coins = #{quarter => 4, dime => 5},
    {ok, NewCoins, Optimized} = vending_machine:optimize_coins(150, Coins, maps:new()),
    0 = maps:size(NewCoins),
    ?assertEqual(Optimized, Coins).

optimize_coins_select_smallest_test() ->
    Coins = #{nickel => 1, dime => 1},
    {ok, NewCoins, Optimized} = vending_machine:optimize_coins(5, Coins, maps:new()),
    ?assertEqual(#{dime => 1}, NewCoins),
    ?assertEqual(#{nickel => 1}, Optimized).

%% Goes over 150 because we have no nickels
optimize_coins_one_fifty_from_quarters_dimes_over_test() ->
    Coins = #{quarter => 3, dime => 8},
    {ok, NewCoins, Optimized} = vending_machine:optimize_coins(150, Coins, maps:new()),
    0 = maps:size(NewCoins),
    ?assertEqual(Coins, Optimized).

optimize_coins_select_nickel_over_dime_test() ->
    Coins = #{quarter => 1, dime => 1, nickel => 1},
    {ok, NewCoins, Optimized} = vending_machine:optimize_coins(30, Coins, maps:new()),
    ?assertEqual(#{dime => 1}, NewCoins),
    ?assertEqual(#{quarter => 1, nickel => 1}, Optimized).

%% Here, we need to select the dime be equal or over 31. The number 31 is
%% obviously contrived because you can't make 31 cents out of nickels, dimes,
%% and quarters.
optimize_coins_select_dime_over_nickel_test() ->
    Coins = #{quarter => 1, dime => 1, nickel => 1},
    {ok, NewCoins, Optimized} = vending_machine:optimize_coins(31, Coins, maps:new()),
    ?assertEqual(#{nickel => 1}, NewCoins),
    ?assertEqual(#{quarter => 1, dime => 1}, Optimized).

add_coins_empty_test() ->
    ?assertEqual(#{}, vending_machine:add_coins(#{}, #{})).

add_coins_not_same_key_test() ->
    X = #{quarter => 1},
    Y = #{nickel => 1},
    ?assertEqual(#{quarter => 1, nickel => 1}, vending_machine:add_coins(X, Y)).

make_change_unable_to_cover_cost_test() ->
    Bank = #{nickel => 1},
    Coins = #{quarter => 1},
    unable_to_cover_cost = vending_machine:make_change(50, Coins, Bank).

make_change_none_necessary_test() ->
    Bank = #{},
    Coins = #{quarter => 1},
    {ok, Change, NewBank} = vending_machine:make_change(25, Coins, Bank),
    ?assertEqual(#{quarter => 1}, NewBank),
    ?assertEqual(#{}, Change).

make_change_simple_test() ->
    Bank = #{nickel => 1},
    Coins = #{quarter => 1},
    {ok, Change, NextBank} = vending_machine:make_change(20, Coins, Bank),
    ?assertEqual(#{quarter => 1}, NextBank),
    ?assertEqual(#{nickel => 1}, Change).

make_change_unable_to_make_change_test() ->
    Bank = #{dime => 1},
    Coins = #{quarter => 1},
    unable_to_make_change = vending_machine:make_change(20, Coins, Bank).

make_change_large_difference_twenty_test() ->
    Bank = #{quarter => 4, dime => 4, nickel => 4},
    Coins = #{quarter => 4, dime => 4, nickel => 4},
    {ok, Change, NextBank} = vending_machine:make_change(20, Coins, Bank),
    ?assertEqual(#{quarter => 4, dime => 4, nickel => 8}, NextBank),
    ?assertEqual(#{quarter => 4, dime => 4}, Change).

make_change_large_difference_twenty_five_test() ->
    Bank = #{quarter => 4, dime => 4, nickel => 4},
    Coins = #{quarter => 4, dime => 4, nickel => 4},
    {ok, Change, NextBank} = vending_machine:make_change(25, Coins, Bank),
    ?assertEqual(#{quarter => 3, dime => 7, nickel => 8}, NextBank),
    ?assertEqual(#{quarter => 5, dime => 1}, Change).

make_change_large_difference_hundred_test() ->
    Bank = #{quarter => 4, dime => 4, nickel => 4},
    Coins = #{quarter => 4, dime => 4, nickel => 4},
    {ok, Change, NextBank} = vending_machine:make_change(100, Coins, Bank),
    ?assertEqual(#{quarter => 6, dime => 7, nickel => 8}, NextBank),
    ?assertEqual(#{quarter => 2, dime => 1}, Change).

make_change_no_change_needed_from_bank_test() ->
    Bank = #{},
    Coins = #{quarter => 6},
    {ok, Change, NextBank} = vending_machine:make_change(100, Coins, Bank),
    ?assertEqual(#{quarter => 4}, NextBank),
    ?assertEqual(#{quarter => 2}, Change).
