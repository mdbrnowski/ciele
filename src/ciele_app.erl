-module(ciele_app).
-moduledoc """
ciele public API
""".

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ciele_sup:start_link().

stop(_State) ->
    ok.
