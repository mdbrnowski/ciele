import ciele/url

// with_scheme/1

pub fn with_scheme_adds_https_test() {
  assert url.with_scheme("example.com") == "https://example.com"
}

pub fn with_scheme_keeps_https_test() {
  assert url.with_scheme("https://example.com") == "https://example.com"
}

pub fn with_scheme_keeps_http_test() {
  assert url.with_scheme("http://example.com") == "http://example.com"
}

pub fn with_scheme_with_path_test() {
  assert url.with_scheme("example.com/path") == "https://example.com/path"
}

// without_scheme/1

pub fn without_scheme_strips_https_test() {
  assert url.without_scheme("https://example.com") == "example.com"
}

pub fn without_scheme_strips_http_test() {
  assert url.without_scheme("http://example.com") == "example.com"
}

pub fn without_scheme_leaves_plain_domain_test() {
  assert url.without_scheme("example.com") == "example.com"
}
