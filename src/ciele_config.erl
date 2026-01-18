-module(ciele_config).

-export([get_domains/0, get_email_address/0, get_sender_email_address/0]).

-define(CONFIG_FILE, "config/config.yaml").

get_config_content() ->
    case filelib:is_file(?CONFIG_FILE) of
        false ->
            logger:error("Config file ~s not found", [?CONFIG_FILE]),
            [];
        true ->
            try
                [Doc] = yamerl_constr:file(?CONFIG_FILE),
                Doc
            catch
                Class:Reason ->
                    logger:error("Failed to load config from ~s: ~p", [?CONFIG_FILE, {Class, Reason}]),
                    []
            end
    end.

-spec get_domains() -> {ok, [string()]} | {error, any()}.
get_domains() ->
    Doc = get_config_content(),
    case proplists:get_value("domains", Doc, undefined) of
        undefined ->
            logger:error("No domains configured in ~s", [?CONFIG_FILE]),
            {error, no_domains};
        Domains when is_list(Domains) ->
            {ok, [lists:flatten(io_lib:format("~ts", [D])) || D <- Domains]};
        _Other ->
            logger:error("Domains entry in ~s is not a list", [?CONFIG_FILE]),
            {error, invalid_domains}
    end.

-spec get_email_address() -> {ok, string()} | {error, any()}.
get_email_address() ->
    Doc = get_config_content(),
    case proplists:get_value("email_address", Doc, undefined) of
        undefined ->
            logger:error("No email_address configured in ~s", [?CONFIG_FILE]),
            {error, no_email_address};
        Email when is_list(Email) ->
            {ok, lists:flatten(io_lib:format("~ts", [Email]))};
        _Other ->
            logger:error("email_address entry in ~s is not a string", [?CONFIG_FILE]),
            {error, invalid_email_address}
    end.

-spec get_sender_email_address() -> {ok, string()} | {error, any()}.
get_sender_email_address() ->
    Doc = get_config_content(),
    case proplists:get_value("sender_email_address", Doc, undefined) of
        undefined ->
            logger:error("No sender_email_address configured in ~s", [?CONFIG_FILE]),
            {error, no_sender_email_address};
        Email when is_list(Email) ->
            {ok, lists:flatten(io_lib:format("~ts", [Email]))};
        _Other ->
            logger:error("sender_email_address entry in ~s is not a string", [?CONFIG_FILE]),
            {error, invalid_sender_email_address}
    end.
