import ciele/server

// to_url/1

pub fn to_url_adds_https_test() {
  assert server.to_url("example.com") == "https://example.com"
}

pub fn to_url_keeps_https_test() {
  assert server.to_url("https://example.com") == "https://example.com"
}

pub fn to_url_keeps_http_test() {
  assert server.to_url("http://example.com") == "http://example.com"
}

pub fn to_url_with_path_test() {
  assert server.to_url("example.com/path") == "https://example.com/path"
}

// comparable_content/1

pub fn comparable_content_extracts_body_test() {
  let html =
    "<html><head><title>x</title></head><body><p>hello</p></body></html>"
  assert server.comparable_content(html) == "<p>hello</p>"
}

pub fn comparable_content_extracts_body_case_insensitive_test() {
  assert server.comparable_content("<HTML><BODY>hello</BODY></HTML>") == "hello"
}

pub fn comparable_content_extracts_body_with_attributes_test() {
  let html = "<html><body class=\"main\" id=\"x\">hello</body></html>"
  assert server.comparable_content(html) == "hello"
}

pub fn comparable_content_falls_back_without_body_test() {
  assert server.comparable_content("plain text") == "plain text"
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
