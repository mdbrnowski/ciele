-module(ciele_server).
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% Callbacks
-export([init/1, handle_call/3, handle_cast/2]).

-define(INTERVAL, 1000 * 60 * 60 * 24). % 24 hours
-define(SITES_FILE, "config/sites.yaml").

%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Callbacks

init([]) ->
    {ok, _} = application:ensure_all_started(yamerl),
    gen_server:cast(self(), check_sites),
    {ok, #{}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(check_sites, State) ->
    io:format("~nStarting site check: ~p~n", [calendar:local_time()]),
    Domains = load_domains_from_yaml(),
    lists:foreach(fun check_and_compare/1, Domains),
    schedule_check(),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

%% Internal functions

-spec load_domains_from_yaml() -> [string()].
load_domains_from_yaml() ->
    try
        [Document] = yamerl_constr:file(?SITES_FILE),
        [{"domains", Domains}] = Document,
        Domains
    catch
        Error:Reason ->
            io:format("Error loading YAML file: ~p: ~p~n", [Error, Reason]),
            []
    end.

-spec check_and_compare(string()) -> ok.
check_and_compare(Domain) ->
    io:format("Checking domain:~n~p~n", [Domain]).

schedule_check() ->
    erlang:send_after(?INTERVAL, self(), {'$gen_cast', check_sites}).
