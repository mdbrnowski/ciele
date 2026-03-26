-module(ciele_diff).

-export([handle_diff/3]).

-ifdef(TEST).
-export([
    remove_https/1,
    escape_html/1,
    to_binary/1,
    build_html/2,
    temp_files/0,
    body_content/1
]).
-endif.

-spec handle_diff(binary(), binary(), string()) -> ok.
handle_diff(OldBin, NewBin, Domain) ->
    {OldPath, NewPath} = temp_files(),
    OldBody = body_content(OldBin),
    NewBody = body_content(NewBin),
    try
        ok = file:write_file(OldPath, OldBody),
        ok = file:write_file(NewPath, NewBody),
        Cmd = io_lib:format("diff -u --label old --label new ~s ~s", [OldPath, NewPath]),
        Diff = os:cmd(lists:flatten(Cmd)),
        logger:info("Diff for ~s:~n~ts", [Domain, Diff]),
        send_email(Diff, Domain)
    after
        file:delete(OldPath),
        file:delete(NewPath)
    end.

-spec temp_files() -> {file:filename_all(), file:filename_all()}.
temp_files() ->
    Suffix = erlang:unique_integer([positive]),
    TmpDir =
        case os:getenv("TMPDIR") of
            false -> "/tmp";
            Dir -> Dir
        end,
    OldPath = filename:join(TmpDir, lists:flatten(io_lib:format("ciele_old_~p.tmp", [Suffix]))),
    NewPath = filename:join(TmpDir, lists:flatten(io_lib:format("ciele_new_~p.tmp", [Suffix]))),
    {OldPath, NewPath}.

-spec send_email(string(), string()) -> ok.
send_email(Diff, Domain) ->
    case os:getenv("RESEND_API_KEY") of
        false ->
            logger:error("RESEND_API_KEY not set, skipping email for ~s", [Domain]);
        ApiKey ->
            ApiKeyBin = to_binary(ApiKey),
            Payload = build_payload(Diff, Domain),
            Headers = [
                {<<"Authorization">>, <<"Bearer ", ApiKeyBin/binary>>},
                {<<"Content-Type">>, <<"application/json">>}
            ],
            Url = "https://api.resend.com/emails",
            Body = jiffy:encode(Payload),
            case hackney:request(post, Url, Headers, Body, []) of
                {ok, Status, _RespHeaders, ClientRef} ->
                    _ = hackney:body(ClientRef),
                    if
                        Status >= 200, Status < 300 ->
                            logger:notice("Sent change email for ~s (status ~p)", [Domain, Status]);
                        true ->
                            logger:error("Email for ~s failed with status ~p", [Domain, Status])
                    end;
                Error ->
                    logger:error("Failed to send email for ~s: ~p", [Domain, Error])
            end
    end.

-spec build_payload(string(), string()) -> map().
build_payload(Diff, Domain) ->
    Subject = iolist_to_binary(
        io_lib:format("Ciele: change detected for ~s", [remove_https(Domain)])
    ),
    HtmlBody = build_html(Diff, Domain),
    {ok, EmailAddress} = ciele_config:get_email_address(),
    {ok, SenderEmailAddress} = ciele_config:get_sender_email_address(),
    #{
        <<"from">> => to_binary("Ciele <" ++ SenderEmailAddress ++ ">"),
        <<"to">> => [to_binary(EmailAddress)],
        <<"subject">> => Subject,
        <<"html">> => HtmlBody,
        <<"reply_to">> => to_binary(SenderEmailAddress)
    }.

-spec remove_https(string()) -> string().
remove_https("https://" ++ Rest) -> Rest;
remove_https("http://" ++ Rest) -> Rest;
remove_https(Url) -> Url.

-spec build_html(string(), string()) -> binary().
build_html(Diff, Domain) ->
    DiffEscaped = escape_html(to_binary(Diff)),
    DomainEscaped = escape_html(to_binary(Domain)),
    iolist_to_binary([
        <<"<p>Change detected for ">>, DomainEscaped,
        <<"</p><pre style=\"white-space:pre-wrap\">">>,
        DiffEscaped,
        <<"</pre>">>
    ]).

-spec to_binary(unicode:chardata()) -> binary().
to_binary(Data) ->
    case unicode:characters_to_binary(Data) of
        Bin when is_binary(Bin) -> Bin;
        {error, _, _} -> iolist_to_binary(io_lib:format("~ts", [Data]));
        {incomplete, _, _} -> iolist_to_binary(io_lib:format("~ts", [Data]))
    end.

-spec body_content(binary()) -> binary().
body_content(Bin) when is_binary(Bin) ->
    case re:run(Bin, <<"(?is)<body\\b[^>]*>(.*?)</body>">>, [{capture, [1], binary}]) of
        {match, [Body]} -> Body;
        nomatch -> Bin
    end.

-spec escape_html(binary()) -> binary().
escape_html(Bin) when is_binary(Bin) ->
    Bin1 = binary:replace(Bin, <<"&">>, <<"&amp;">>, [global]),
    Bin2 = binary:replace(Bin1, <<"<">>, <<"&lt;">>, [global]),
    Bin3 = binary:replace(Bin2, <<">">>, <<"&gt;">>, [global]),
    binary:replace(Bin3, <<"\"">>, <<"&quot;">>, [global]).
