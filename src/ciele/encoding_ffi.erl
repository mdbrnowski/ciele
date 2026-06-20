-module(encoding_ffi).
-export([lossy_utf8/1]).

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
