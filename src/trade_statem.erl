%% Converting the gen_fsm to gen_statem code here. The chapter uses the gen_fsm
%% behaviour, but that is deprecated.
%% https://learnyousomeerlang.com/finite-state-machines#game-trading-between-two-players
-module(trade_statem).
-behaviour(gen_statem).

%% Public API
-export([
    start/1,
    start_link/1,
    trade/2,
    accept_trade/1,
    make_offer/2,
    retract_offer/2,
    ready/1,
    cancel/1
]).

%% gen_state callbacks
-export([
    init/1,
    callback_mode/0,
    terminate/3,
    code_change/4,

    idle/2,
    idle/3,
    idle_wait/2,
    idle_wait/3,
    negotiate/2,
    negotiate/3,
    wait/2,
    ready/2,
    ready/3
]).

%% A player's name
start(Name) ->
    gen_start:start(?MODULE, [Name], []).

start_link(Name) ->
    gen_statem:start_link(?MODULE, [Name], []).

callback_mode() ->
    state_functions.

trade(OwnPid, OtherPid) ->
    gen_statem:call(OwnPid, {negotiate, OtherPid}, 30000).

accept_trade(OwnPid) ->
    gen_statem:call(OwnPid, accept_negotiate).

make_offer(OwnPid, Item) ->
    gen_statem:cast(OwnPid, {make_offer, Item}).

retract_offer(OwnPid, Item) ->
    gen_statem:cast(OwnPid, {retract_offer, Item}).

ready(OwnPid) ->
    gen_statem:call(OwnPid, ready, infinity).

cancel(OwnPid) ->
    gen_statem:call(OwnPid, cancel).

ask_negotiate(OtherPid, OwnPid) ->
    gen_statem:cast(OtherPid, {ask_negotiate, OwnPid}).

accept_negotiate(OtherPid, OwnPid) ->
    gen_statem:cast(OtherPid, {accept_negotiate, OwnPid}).

do_offer(OtherPid, Item) ->
    gen_statem:cast(OtherPid, {do_offer, Item}).

undo_offer(OtherPid, Item) ->
    gen_statem:cast(OtherPid, {undo_offer, Item}).

are_you_ready(OtherPid) ->
    gen_statem:cast(OtherPid, are_you_ready).

not_yet(OtherPid) ->
    gen_statem:cast(OtherPid, not_yet).

am_ready(OtherPid) ->
    gen_statem:cast(OtherPid, 'ready!').

acknowledge_transfer(OtherPid) ->
    gen_statem:cast(OtherPid, acknowledge).

ask_commit(OtherPid) ->
    gen_statem:call(OtherPid, ask_commit).

do_commit(OtherPid) ->
    gen_statem:call(OtherPid, do_commit).

-record(state, {
    name = "",
    other,
    own_items = [],
    other_items = [],
    monitor,
    from
}).

commit(S = #state{}) ->
    io:format(
        "Transaction complete for ~s. "
        "Items sent are: ~n~p,~n recieved:~n~p.~n",
        [S#state.name, S#state.own_items, S#state.other_items]
    ).

init(Name) ->
    {ok, idle, #state{name = Name}}.

notice(#state{name = Name}, Str, Args) ->
    io:format("~s: " ++ Str ++ "~n", [Name | Args]).

unexpected(Msg, State) ->
    io:format(
        "~p recieved unknown event ~p while in state ~p~n",
        [self(), Msg, State]
    ).

idle({ask_negotiate, OtherPid}, S = #state{}) ->
    Ref = monitor(process, OtherPid),
    notice(S, "~p asked for a trade negotiation", [OtherPid]),
    {next_state, idle_wait, S#state{other = OtherPid, monitor = Ref}};
idle(Event, Data) ->
    unexpected(Event, idle),
    {next_state, idle, Data}.

idle({negotiate, OtherPid}, From, S = #state{}) ->
    ask_negotiate(OtherPid, self()),
    notice(S, "asking user ~p for a trade", [OtherPid]),
    Ref = monitor(process, OtherPid),
    {next_state, idle_wait, S#state{other = OtherPid, monitor = Ref, from = From}};
idle(Event, _From, Data) ->
    unexpected(Event, idle),
    {next_state, idle, Data}.

idle_wait({ask_negotiate, OtherPid}, S = #state{other = OtherPid}) ->
    gen_statem:reply(S#state.from, ok),
    notice(S, "starting negotiation", []),
    {next_state, negotiate, S};
idle_wait({accept_negotiate, OtherPid}, S = #state{other = OtherPid}) ->
    gen_statem:reply(S#state.from, ok),
    notice(S, "starting negotiation", []),
    {next_state, negotiate, S};
idle_wait(Event, Data) ->
    unexpected(Event, idle_wait),
    {next_state, idle_wait, Data}.

idle_wait(accept_negotiate, _From, S = #state{other = OtherPid}) ->
    accept_negotiate(OtherPid, self()),
    notice(S, "accepting negotiation", []),
    {reply, ok, negotiate, S};
idle_wait(Event, _From, Data) ->
    unexpected(Event, idle_wait),
    {next_state, idle_wait, Data}.

add_item(Item, Items) ->
    [Item | Items].

remove_item(Item, Items) ->
    Items -- [Item].

negotiate({make_offer, Item}, S = #state{own_items = OwnItems}) ->
    do_offer(S#state.other, Item),
    notice(S, "offering ~p", [Item]),
    {next_state, negotiate, S#state{own_items = add_item(Item, OwnItems)}};
negotiate({retract_offer, Item}, S = #state{own_items = OwnItems}) ->
    undo_offer(S#state.other, Item),
    notice(S, "cancelling offer on ~p", [Item]),
    {next_state, negotiate, S#state{own_items = remove_item(Item, OwnItems)}};
negotiate({do_offer, Item}, S = #state{other_items = OtherItems}) ->
    notice(S, "other player offering ~p", [Item]),
    {next_state, negotiate, S#state{other_items = add_item(Item, OtherItems)}};
negotiate({undo_offer, Item}, S = #state{other_items = OtherItems}) ->
    notice(S, "other player retracting ~p", [Item]),
    {next_state, negotiate, S#state{other_items = remove_item(Item, OtherItems)}};
negotiate(are_you_ready, S = #state{other = OtherPid}) ->
    io:format("Other user is ready to trade.~n"),
    notice(
        S,
        "Other user ready to transfer goods: ~n"
        "You get ~p, The other side gets ~p",
        [S#state.other_items, S#state.own_items]
    ),
    not_yet(OtherPid),
    {next_state, negotiate, S};
negotiate(Event, Data) ->
    unexpected(Event, negotiate),
    {next_state, negotiate, Data}.

negotiate(ready, From, S = #state{other = OtherPid}) ->
    are_you_ready(OtherPid),
    notice(S, "asking if ready, waiting...", []),
    {next_state, wait, S#state{from = From}};
negotiate(Event, _From, Data) ->
    unexpected(Event, negotiate),
    {next_state, negotiate, Data}.

wait({do_offer, Item}, S = #state{other_items = OtherItems}) ->
    gen_statem:call(S#state.from, offer_changed),
    notice(S, "other side offering ~p", [Item]),
    {next_state, negotiate, S#state{other_items = add_item(Item, OtherItems)}};
wait({undo_offer, Item}, S = #state{other_items = OtherItems}) ->
    gen_statem:call(S#state.from, offer_changed),
    notice(S, "other side cancelling offer of ~p", [Item]),
    {next_state, negotiate, S = #state{other_items = remove_item(Item, OtherItems)}};
wait(are_you_ready, S = #state{}) ->
    am_ready(S#state.other),
    notice(S, "asked if ready, I am. waiting for reply", []),
    {next_state, wait, S};
wait(not_yet, S = #state{}) ->
    notice(S, "Other side not ready yet", []),
    {next_state, wait, S};
wait('ready!', S = #state{}) ->
    am_ready(S#state.other),
    acknowledge_transfer(S#state.other),
    gen_statem:call(S#state.from, ok),
    notice(S, "Other side is ready, Moving to ready", []),
    {next_state, ready, S};
wait(Event, Data) ->
    unexpected(Event, negotiate),
    {next_state, wait, Data}.

priority(OwnPid, OtherPid) when OwnPid > OtherPid -> true;
priority(OwnPid, OtherPid) when OwnPid < OtherPid -> false.

ready(acknowledge, S = #state{}) ->
    case priority(self(), S#state.other) of
        true ->
            try
                notice(S, "asking for commit", []),
                ready_commit = ask_commit(S#state.other),
                notice(S, "ordering commit", []),
                ok = do_commit(S#state.other),
                notice(S, "committing...", []),
                commit(S),
                {stop, normal, S}
            catch
                Class:Reason ->
                    notice(S, "commit failed...", []),
                    {stop, {Class, Reason}, S}
            end;
        false ->
            {next_state, ready, S}
    end;
ready(Event, Data) ->
    unexpected(Event, ready),
    {next_state, ready, Data}.

ready(ask_commit, _From, S) ->
    notice(S, "replying to ask_commit", []),
    {reply, ready_commit, ready, S};
ready(do_commit, _From, S) ->
    notice(S, "commit!", []),
    {stop, normal, ok, S};
ready(Event, _From, Data) ->
    unexpected(Event, ready),
    {next_state, ready, Data}.

code_change(_OldVersion, StateName, Data, _Extra) ->
    {ok, StateName, Data}.

terminate(normal, ready, S = #state{}) ->
    notice(S, "FSM leaving", []);
terminate(_Reason, _StateName, _StateData) ->
    ok.
