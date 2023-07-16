%%% API Module for pools
-module(ppool).
-export([
    start_link/0,
    stop/0,
    start_pool/3,
    run/2,
    sync_queue/2,
    async_queue/2,
    stop_pool/1
]).

start_link() ->
    ppool_main_supervisor:start_link().

stop() ->
    ppool_main_supervisor:stop().

start_pool(Name, Limit, {M, F, A}) ->
    ppool_main_supervisor:start_pool(Name, Limit, {M, F, A}).

stop_pool(Name) ->
    ppool_main_supervisor:stop_pool(Name).

run(Name, Args) ->
    ppool_server:run(Name, Args).

sync_queue(Name, Args) ->
    ppool_server:sync_queue(Name, Args).

async_queue(Name, Args) ->
    ppool_server:async_queue(Name, Args).
