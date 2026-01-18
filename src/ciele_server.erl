-module(ciele_server).
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% Callbacks
-export([init/1, handle_call/3, handle_cast/2]).

-define(INTERVAL, 1000 * 60 * 60 * 6). % 6 hours

%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Callbacks

init([]) ->
    {ok, _} = application:ensure_all_started(yamerl),
    {ok, _} = application:ensure_all_started(hackney),
    case os:getenv("RESEND_API_KEY") of
        false ->
            logger:error("RESEND_API_KEY environment variable not set."),
            exit(no_email_api_key);
        _ApiKey ->
            ok
    end,
    Table = ets:new(ciele_checks, [named_table, set, public, {read_concurrency, true}]),
    gen_server:cast(self(), check_sites),
    {ok, #{table => Table}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(check_sites, State) ->
    {ok, Domains} = ciele_config:get_domains(),
    logger:notice("Loaded ~p domains to check. Starting checks...", [length(Domains)]),
    lists:foreach(fun(Domain) -> check_and_compare(Domain, State) end, Domains),
    logger:notice("All domain checks completed. Scheduling next check in ~p s.", [
        (?INTERVAL) / 1000
    ]),
    schedule_check(),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

%% Internal functions

-spec check_and_compare(string(), map()) -> ok.
check_and_compare(Domain, State) ->
    Table = maps:get(table, State),
    Url = to_url(Domain),
    logger:info("Checking domain: ~s", [Url]),
    case fetch_body(Url) of
        {ok, Body} ->
            maybe_log_change(Domain, Body, Table),
            ets:insert(Table, {Domain, Body}),
            ok;
        {error, Reason} ->
            logger:warning("Failed to fetch ~s: ~p", [Url, Reason]),
            ok
    end.

-spec to_url(string()) -> string().
to_url(Domain) ->
    case string:prefix(Domain, "http") of
        nomatch -> "https://" ++ Domain;
        _ -> Domain
    end.

-spec fetch_body(string()) -> {ok, binary()} | {error, any()}.
fetch_body(Url) ->
    case hackney:request(get, Url, [], <<>>, []) of
        {ok, Status, _Headers, ClientRef} when Status >= 200, Status < 400 ->
            case hackney:body(ClientRef) of
                {ok, Body} -> {ok, Body};
                Error -> {error, Error}
            end;
        {ok, Status, _Headers, ClientRef} ->
            _ = hackney:body(ClientRef),
            {error, {unexpected_status, Status}};
        Error ->
            {error, Error}
    end.

-spec maybe_log_change(string(), binary(), ets:tid()) -> ok.
maybe_log_change(Domain, Body, Table) ->
    case ets:lookup(Table, Domain) of
        [{Domain, Body}] ->
            logger:info("No change for ~s", [Domain]);
        [{Domain, OldBody}] ->
            logger:notice("Content changed for ~s (~p -> ~p bytes)", [
                Domain, byte_size(OldBody), byte_size(Body)
            ]),
            ciele_diff:handle_diff(OldBody, Body, Domain);
        [] ->
            logger:notice("First check recorded for ~s (~p bytes)", [Domain, byte_size(Body)])
    end.

-spec schedule_check() -> reference().
schedule_check() ->
    erlang:send_after(?INTERVAL, self(), {'$gen_cast', check_sites}).
