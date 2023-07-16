-module(ppool_server).
-behavior(gen_server).

-export([
    start/4,
    start_link/4,
    run/2,
    sync_queue/2,
    async_queue/2,
    stop/1,

    % gen_server minimum
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    code_change/3,
    terminate/2
]).

%% Our public API
start(Name, Limit, Sup, MFA) when is_atom(Name), is_integer(Limit) ->
    gen_server:start({local, Name}, ?MODULE, {Limit, MFA, Sup}, []).

start_link(Name, Limit, Sup, MFA) when is_atom(Name), is_integer(Limit) ->
    gen_server:start_link({local, Name}, ?MODULE, {Limit, MFA, Sup}, []).

run(Name, Args) ->
    gen_server:call(Name, {run, Args}).

sync_queue(Name, Args) ->
    gen_server:call(Name, {sync, Args}, infinity).

async_queue(Name, Args) ->
    gen_server:cast(Name, {async, Args}).

stop(Name) ->
    gen_server:stop(Name, stop).

%% The worker supervisor is started dynamically
-define(SPEC(MFA),
    {worker_supervisor, {ppool_worker_supervisor, start_link, [MFA]}, temporary, 10000, supervisor,
        [ppool_worker_supervisor]}
).

-record(state, {
    limit = 0 :: integer(),
    sup,
    refs,
    queue = queue:new()
}).

init({Limit, MFA, Sup}) ->
    self() ! {start_worker_supervisor, Sup, MFA},
    {ok, #state{limit = Limit, refs = gb_sets:empty()}}.

handle_info({'DOWN', Ref, process, _Pid, _}, S = #state{refs = Refs}) ->
    io:format("Got DOWN message~n"),
    case gb_sets:is_element(Ref, Refs) of
        true ->
            handle_down_worker(Ref, S);
        false ->
            {noreply, S}
    end;
handle_info({start_worker_supervisor, Sup, MFA}, S = #state{}) ->
    {ok, Pid} = supervisor:start_child(Sup, ?SPEC(MFA)),
    link(Pid),
    {noreply, S#state{sup = Pid}};
handle_info(Msg, S = #state{}) ->
    io:format("Unknown message: ~p~n", [Msg]),
    {noreply, S}.

%% We can only run a process if the Limit is greater than zero
%% Otherwise, we do nothing
handle_call({run, Args}, _From, S = #state{limit = N, sup = Sup, refs = Refs}) when N > 0 ->
    {ok, Pid} = supervisor:start_child(Sup, Args),
    Ref = erlang:monitor(process, Pid),
    {reply, {ok, Pid}, S#state{limit = N - 1, refs = gb_sets:add(Ref, Refs)}};
handle_call({run, _Args}, _From, S = #state{}) ->
    {reply, noalloc, S};
%% A synchronous job can be run immediately if there is space in the pool
%% Otherwise, we queue up the job to be completed and will notify the caller when done
handle_call({sync, Args}, _From, S = #state{limit = N, sup = Sup, refs = Refs}) when N > 0 ->
    {ok, Pid} = supervisor:start_child(Sup, Args),
    Ref = erlang:monitor(process, Pid),
    {reply, {ok, Pid}, S#state{limit = N - 1, refs = gb_sets:add(Ref, Refs)}};
handle_call({sync, Args}, From, S = #state{queue = Q}) ->
    {noreply, S#state{queue = queue:in({From, Args}, Q)}};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call(_Msg, _From, State) ->
    {noreply, State}.

handle_cast({async, Args}, S = #state{limit = N, sup = Sup, refs = R}) when N > 0 ->
    {ok, Pid} = supervisor:start_child(Sup, Args),
    Ref = erlang:monitor(process, Pid),
    {noreply, S#state{limit = N - 1, refs = gb_sets:add(Ref, R)}};
handle_cast({async, Args}, S = #state{limit = N, queue = Q}) when N =< 0 ->
    {noreply, S#state{queue = queue:in(Args, Q)}};
handle_cast(_Msg, State) ->
    {noreply, State}.

code_change(_OldVersion, State, _Extras) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

handle_down_worker(Ref, S = #state{limit = L, sup = Sup, refs = Refs}) ->
    case queue:out(S#state.queue) of
        {{value, {From, Args}}, Q} ->
            % start the next worker, set up the new reference set, due to
            % 'From' we know this came from synchronous call so we need to
            % reply!
            {ok, Pid} = supervisor:start_child(Sup, Args),
            NewRef = erlang:monitor(process, Pid),
            NewRefs = gb_sets:insert(NewRef, gb_sets:delete(Ref, Refs)),
            gen_server:reply(From, {ok, Pid}),
            {noreply, S#state{refs = NewRefs, queue = Q}};
        {{value, Args}, Q} ->
            {ok, Pid} = supervisor:start_child(Sup, Args),
            NewRef = erlang:monitor(process, Pid),
            NewRefs = gb_sets:insert(NewRef, gb_sets:delete(Ref, Refs)),
            {noreply, S#state{refs = NewRefs, queue = Q}};
        {empty, _} ->
            {noreply, S#state{limit = L + 1, refs = gb_sets:delete(Ref, Refs)}}
    end.
