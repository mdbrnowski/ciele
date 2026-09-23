-module(ciele_ffi).
-export([lossy_utf8/1, fetch_tls12/2, configure_timestamps/0, format/2,
         write_sync/2, sync_directory/1]).

%% Fetch `Url' over HTTPS forcing a TLS 1.2 handshake.
fetch_tls12(Url, UserAgent) ->
    application:ensure_all_started(inets),
    application:ensure_all_started(ssl),
    SslOpts = [{versions, ['tlsv1.2']},
               {verify, verify_peer},
               {cacerts, public_key:cacerts_get()},
               {customize_hostname_check,
                [{match_fun,
                  public_key:pkix_verify_hostname_match_fun(https)}]}],
    HttpOpts = [{ssl, SslOpts}, {timeout, 30000}, {autoredirect, false}],
    Opts = [{body_format, binary}, {socket_opts, [{ipfamily, inet6fb4}]}],
    Headers = [{"user-agent", binary_to_list(UserAgent)}],
    case httpc:request(get, {binary_to_list(Url), Headers}, HttpOpts, Opts) of
        {ok, {{_Version, Status, _Reason}, _Headers, Body}} ->
            {ok, {Status, Body}};
        {error, _Reason} ->
            {error, nil}
    end.

%% Decode `Bin' as UTF-8, keeping every valid sequence intact and replacing each
%% invalid byte with the Unicode replacement character (U+FFFD, "?").
lossy_utf8(Bin) ->
    lossy_utf8(Bin, <<>>).

lossy_utf8(<<>>, Acc) ->
    Acc;
lossy_utf8(Bin, Acc) ->
    case unicode:characters_to_binary(Bin, utf8, utf8) of
        Decoded when is_binary(Decoded) ->
            <<Acc/binary, Decoded/binary>>;
        {error, Valid, <<_Bad, Tail/binary>>} ->
            lossy_utf8(Tail, <<Acc/binary, Valid/binary, 16#EF, 16#BF, 16#BD>>);
        {incomplete, Valid, _Rest} ->
            <<Acc/binary, Valid/binary, 16#EF, 16#BF, 16#BD>>
    end.

%% Reconfigure the default logger handler so every line is prefixed with a
%% local-time timestamp. Must be called after logging:configure/0.
configure_timestamps() ->
    case logger:get_handler_config(default) of
        {ok, #{formatter := {_Module, FormatterConfig}}} ->
            logger:update_handler_config(default, #{
                formatter => {ciele_ffi, FormatterConfig}
            });
        _ ->
            ok
    end,
    nil.

%% Logger formatter callback: prepend a timestamp in the system's local
%% timezone, then defer to logging_ffi for the level + message rendering.
format(#{meta := Meta} = Event, Config) ->
    Time = maps:get(time, Meta, erlang:system_time(microsecond)),
    Universal = calendar:system_time_to_universal_time(Time, microsecond),
    {{Y, Mo, D}, {H, Mi, S}} = calendar:universal_time_to_local_time(Universal),
    Timestamp = io_lib:format(
        "~4..0b-~2..0b-~2..0b ~2..0b:~2..0b:~2..0b",
        [Y, Mo, D, H, Mi, S]
    ),
    [Timestamp, $\s, logging_ffi:format(Event, Config)].

%% Write `Contents' to `Path', flushed to disk, so the rename in
%% `ciele@store:save/1' cannot be committed ahead of the data.
write_sync(Path, Contents) ->
    case file:open(Path, [write, raw, binary]) of
        {ok, Fd} ->
            Result = case file:write(Fd, Contents) of
                         ok -> file:sync(Fd);
                         WriteError -> WriteError
                     end,
            _ = file:close(Fd),
            case Result of
                ok -> {ok, nil};
                {error, Reason} -> {error, describe_file_error(Reason)}
            end;
        {error, Reason} ->
            {error, describe_file_error(Reason)}
    end.

%% Flush `Dir' itself, so a rename inside it survives a power cut.
sync_directory(Dir) ->
    _ = os:cmd("sync " ++ binary_to_list(Dir)),
    nil.

describe_file_error(Reason) ->
    unicode:characters_to_binary(file:format_error(Reason)).
