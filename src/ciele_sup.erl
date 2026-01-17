-module(ciele_sup).
-moduledoc """
ciele top level supervisor.
""".

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 1,
        period => 5
    },
    ChildSpecs = [
        #{
            id => ciele_server,
            start => {ciele_server, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [ciele_server]
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.
