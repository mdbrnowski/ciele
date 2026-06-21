-module(encoding_ffi).
-export([lossy_utf8/1, fetch_tls12/2]).

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
