-module(ciele_server_tests).
-include_lib("eunit/include/eunit.hrl").

%%--------------------------------------------------------------------
%% to_url/1
%%--------------------------------------------------------------------

to_url_adds_https_test() ->
    ?assertEqual("https://example.com", ciele_server:to_url("example.com")).

to_url_keeps_https_test() ->
    ?assertEqual("https://example.com", ciele_server:to_url("https://example.com")).

to_url_keeps_http_test() ->
    ?assertEqual("http://example.com", ciele_server:to_url("http://example.com")).

to_url_with_path_test() ->
    ?assertEqual("https://example.com/path", ciele_server:to_url("example.com/path")).
