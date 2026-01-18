-module(ciele_config).

-export([get_domains/0]).

-define(CONFIG_FILE, "config/config.yaml").

-spec get_domains() -> [string()].
get_domains() ->
    case filelib:is_file(?CONFIG_FILE) of
        false ->
            logger:error("Config file ~s not found", [?CONFIG_FILE]),
            [];
        true ->
            try
                [Doc] = yamerl_constr:file(?CONFIG_FILE),
                handle_doc(Doc)
            catch
                Class:Reason ->
                    logger:error("Failed to load config from ~s: ~p", [?CONFIG_FILE, {Class, Reason}]),
                    []
            end
    end.

-spec handle_doc(term()) -> [string()].
handle_doc(Doc) when is_list(Doc) ->
    case proplists:get_value("domains", Doc, undefined) of
        undefined ->
            logger:error("No domains configured in ~s", [?CONFIG_FILE]),
            [];
        Domains when is_list(Domains) ->
            [lists:flatten(io_lib:format("~ts", [D])) || D <- Domains];
        _Other ->
            logger:error("Domains entry in ~s is not a list", [?CONFIG_FILE]),
            []
    end;
handle_doc(_Doc) ->
    logger:error("Config content in ~s is not a proplist", [?CONFIG_FILE]),
    [].
