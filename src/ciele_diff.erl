-module(ciele_diff).

-export([handle_diff/3]).

-spec handle_diff(binary(), binary(), string()) -> ok.
handle_diff(OldBin, NewBin, Domain) ->
    {OldPath, NewPath} = temp_files(),
    try
        ok = file:write_file(OldPath, OldBin),
        ok = file:write_file(NewPath, NewBin),
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
send_email(_Diff, _Domain) ->
    % todo: implement email sending
    ok.
