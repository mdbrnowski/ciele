-module(ciele_diff_tests).
-include_lib("eunit/include/eunit.hrl").

%%--------------------------------------------------------------------
%% remove_https/1
%%--------------------------------------------------------------------

remove_https_strips_https_test() ->
    ?assertEqual("example.com", ciele_diff:remove_https("https://example.com")).

remove_https_strips_http_test() ->
    ?assertEqual("example.com", ciele_diff:remove_https("http://example.com")).

remove_https_leaves_plain_domain_test() ->
    ?assertEqual("example.com", ciele_diff:remove_https("example.com")).

%%--------------------------------------------------------------------
%% escape_html/1
%%--------------------------------------------------------------------

escape_html_ampersand_test() ->
    ?assertEqual(<<"a&amp;b">>, ciele_diff:escape_html(<<"a&b">>)).

escape_html_lt_gt_test() ->
    ?assertEqual(<<"&lt;div&gt;">>, ciele_diff:escape_html(<<"<div>">>)).

escape_html_quote_test() ->
    ?assertEqual(<<"&amp;quot;">>, ciele_diff:escape_html(<<"&quot;">>)).

escape_html_combined_test() ->
    ?assertEqual(
        <<"&lt;a href=&quot;x&amp;y&quot;&gt;">>,
        ciele_diff:escape_html(<<"<a href=\"x&y\">">>)
    ).

escape_html_no_special_chars_test() ->
    ?assertEqual(<<"hello world">>, ciele_diff:escape_html(<<"hello world">>)).

escape_html_empty_test() ->
    ?assertEqual(<<>>, ciele_diff:escape_html(<<>>)).

%%--------------------------------------------------------------------
%% to_binary/1
%%--------------------------------------------------------------------

to_binary_string_test() ->
    ?assertEqual(<<"hello">>, ciele_diff:to_binary("hello")).

to_binary_binary_test() ->
    ?assertEqual(<<"hello">>, ciele_diff:to_binary(<<"hello">>)).

to_binary_unicode_test() ->
    ?assertEqual(<<"café"/utf8>>, ciele_diff:to_binary("café")).

to_binary_empty_test() ->
    ?assertEqual(<<>>, ciele_diff:to_binary("")).

%%--------------------------------------------------------------------
%% build_html/2
%%--------------------------------------------------------------------

build_html_basic_test() ->
    Result = ciele_diff:build_html("some diff", "https://example.com"),
    ?assert(is_binary(Result)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"example.com">>)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"some diff">>)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"<pre">>)).

build_html_escapes_domain_test() ->
    Result = ciele_diff:build_html("diff", "<script>alert(1)</script>"),
    ?assertEqual(nomatch, binary:match(Result, <<"<script>">>)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"&lt;script&gt;">>)).

build_html_escapes_diff_test() ->
    Result = ciele_diff:build_html("<b>bold</b>", "example.com"),
    ?assertEqual(nomatch, binary:match(Result, <<"<b>">>)),
    ?assertNotEqual(nomatch, binary:match(Result, <<"&lt;b&gt;">>)).

%%--------------------------------------------------------------------
%% temp_files/0
%%--------------------------------------------------------------------

temp_files_returns_two_paths_test() ->
    {Old, New} = ciele_diff:temp_files(),
    ?assert(is_list(Old)),
    ?assert(is_list(New)),
    ?assertNotEqual(Old, New).

temp_files_unique_test() ->
    {Old1, New1} = ciele_diff:temp_files(),
    {Old2, New2} = ciele_diff:temp_files(),
    ?assertNotEqual(Old1, Old2),
    ?assertNotEqual(New1, New2).

temp_files_contain_ciele_prefix_test() ->
    {Old, New} = ciele_diff:temp_files(),
    ?assertNotEqual(nomatch, string:find(Old, "ciele_old_")),
    ?assertNotEqual(nomatch, string:find(New, "ciele_new_")).
