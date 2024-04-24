-module(boss_pool).
-export([call/2, call/3, checkout_connected_worker/1]).

-define(MAXDELAY, 60000).
-define(CONNECTION_TIMEOUT_SEED, 1000).
-define(GENSERVER_TIMEOUT, (30 * 1000)).

call(Pool, Msg) ->
    Worker = poolboy:checkout(Pool),
    Reply = gen_server:call(Worker, Msg),
    poolboy:checkin(Pool, Worker),
    Reply.

call(Pool, Msg, Timeout) ->
    case checkout_connected_worker(Pool) of
        {ok, Worker} ->
            Reply = gen_server:call(Worker, Msg, Timeout),
            poolboy:checkin(Pool, Worker),
            Reply;
        Response ->
            Response
    end.

%% @doc automatically checks in a worker if couldn't succeed in finding a connected one
checkout_connected_worker(Pool) ->
    Worker = poolboy:checkout(Pool, true, ?GENSERVER_TIMEOUT),
    case wait_until_connected(Worker) of
        {ok, connected} ->
            {ok, Worker};
        Response ->
            poolboy:checkin(Pool, Worker),
            Response
    end.

wait_until_connected(Worker) ->
    wait_until_connected(Worker, ?CONNECTION_TIMEOUT_SEED).

wait_until_connected(Worker, Timeout) ->
    case gen_server:call(Worker, {get_connection_state}, ?GENSERVER_TIMEOUT) of
        connected ->
            {ok, connected};
        Return ->
            case Timeout >= ?MAXDELAY of
                true ->
                    lager:error("Return = ~p,  Connection retry limit reached for worker: ~p", [
                        Return, Worker
                    ]),
                    {error, connection_retry_limit_exceeded};
                _ ->
                    lager:warning(
                        "Return = ~p, Boss pool worker: ~p not connected. Retrying in ~p", [
                            Return, Worker, Timeout * 2
                        ]
                    ),
                    timer:sleep(Timeout * 2),
                    wait_until_connected(Worker, Timeout * 2)
            end
    end.
