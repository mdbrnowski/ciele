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

%%--------------------------------------------------------------------
%% comparable_content/1
%%--------------------------------------------------------------------

comparable_content_extracts_body_test() ->
    Html = <<"<html><head><title>x</title></head><body><p>hello</p></body></html>">>,
    ?assertEqual(<<"<p>hello</p>">>, ciele_server:comparable_content(Html)).

comparable_content_extracts_body_case_insensitive_test() ->
    Html = <<"<HTML><BODY>hello</BODY></HTML>">>,
    ?assertEqual(<<"hello">>, ciele_server:comparable_content(Html)).

comparable_content_extracts_body_with_attributes_test() ->
    Html = <<"<html><body class=\"main\" id=\"x\">hello</body></html>">>,
    ?assertEqual(<<"hello">>, ciele_server:comparable_content(Html)).

comparable_content_falls_back_without_body_test() ->
    Input = <<"plain text">>,
    ?assertEqual(Input, ciele_server:comparable_content(Input)).
