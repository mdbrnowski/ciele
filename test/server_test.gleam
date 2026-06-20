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
