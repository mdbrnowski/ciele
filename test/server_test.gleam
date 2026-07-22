import ciele/server

// comparable_content/3

pub fn comparable_content_extracts_pretty_body_test() {
  let html =
    "<html><head><title>x</title></head><body><p>hello</p></body></html>"
  assert server.comparable_content(html, [], False)
    == "<body>\n  <p>\n    hello\n  </p>\n</body>\n"
}

pub fn comparable_content_extracts_body_case_insensitive_test() {
  assert server.comparable_content("<HTML><BODY>HELLO</BODY></HTML>", [], False)
    == "<body>\n  HELLO\n</body>\n"
}

pub fn comparable_content_keeps_body_attributes_test() {
  let html = "<html><body class=\"main\" id=\"x\">hello</body></html>"
  assert server.comparable_content(html, [], False)
    == "<body class=\"main\" id=\"x\">\n  hello\n</body>\n"
}

pub fn comparable_content_removes_scripts_test() {
  let html =
    "<html><body><p>hi</p><script>var a = 1;</script><b>x</b></body></html>"
  assert server.comparable_content(html, [], False)
    == "<body>\n  <p>\n    hi\n  </p>\n  <b>\n    x\n  </b>\n</body>\n"
}

pub fn comparable_content_falls_back_without_body_test() {
  assert server.comparable_content("plain text", [], False) == "plain text"
}

pub fn comparable_content_removes_tags_test() {
  let html =
    "<html><body><p>keep</p><script>x</script><div>ciao</div></body></html>"
  assert server.comparable_content(html, ["body div"], False)
    == "<body>\n  <p>\n    keep\n  </p>\n</body>\n"
}

pub fn comparable_content_removes_classes_test() {
  let html =
    "<html><body><p>keep</p><script>x</script><div class=\"ads\">ciao</div></body></html>"
  assert server.comparable_content(html, ["div.ads"], False)
    == "<body>\n  <p>\n    keep\n  </p>\n</body>\n"
}

pub fn comparable_content_removes_ids_test() {
  let html =
    "<html><body><p>keep</p><script>x</script><div id=\"ads\">ciao</div></body></html>"
  assert server.comparable_content(html, ["div#ads"], False)
    == "<body>\n  <p>\n    keep\n  </p>\n</body>\n"
}

pub fn comparable_content_removes_pseudo_classes_test() {
  let html =
    "<html><body><p>keep</p><script>x</script><p>ciao</p></body></html>"
  assert server.comparable_content(html, ["p:nth-of-type(2)"], False)
    == "<body>\n  <p>\n    keep\n  </p>\n</body>\n"
}

pub fn comparable_content_skips_invalid_selectors_test() {
  let html =
    "<html><body><p>keep</p><script>x</script><bold>ciao</bold></body></html>"
  assert server.comparable_content(html, ["p:unreal-state", "bold"], False)
    == "<body>\n  <p>\n    keep\n  </p>\n</body>\n"
}

pub fn comparable_content_strips_classes_when_ignoring_test() {
  let html =
    "<html><body class=\"main\" id=\"x\"><p class=\"a b\">hi</p></body></html>"
  assert server.comparable_content(html, [], True)
    == "<body id=\"x\">\n  <p>\n    hi\n  </p>\n</body>\n"
}

pub fn comparable_content_keeps_classes_when_not_ignoring_test() {
  let html = "<html><body><p class=\"a b\">hi</p></body></html>"
  assert server.comparable_content(html, [], False)
    == "<body>\n  <p class=\"a b\">\n    hi\n  </p>\n</body>\n"
}

// decode_body/1

pub fn decode_body_keeps_valid_utf8_test() {
  assert server.decode_body(<<"zażółć gęślą jaźń":utf8>>) == "zażółć gęślą jaźń"
}

pub fn decode_body_replaces_invalid_byte_without_failing_test() {
  assert server.decode_body(<<"foo", 0xB3, "bar">>) == "foo\u{FFFD}bar"
}

pub fn decode_body_keeps_valid_utf8_around_a_bad_byte_test() {
  assert server.decode_body(<<"zażółć ", 0xC3, " jaźń":utf8>>)
    == "zażółć \u{FFFD} jaźń"
}
