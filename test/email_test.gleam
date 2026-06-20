import ciele/email
import gleam/string

// remove_https/1

pub fn remove_https_strips_https_test() {
  assert email.remove_https("https://example.com") == "example.com"
}

pub fn remove_https_strips_http_test() {
  assert email.remove_https("http://example.com") == "example.com"
}

pub fn remove_https_leaves_plain_domain_test() {
  assert email.remove_https("example.com") == "example.com"
}

// escape_html/1

pub fn escape_html_ampersand_test() {
  assert email.escape_html("a&b") == "a&amp;b"
}

pub fn escape_html_lt_gt_test() {
  assert email.escape_html("<div>") == "&lt;div&gt;"
}

pub fn escape_html_quote_test() {
  assert email.escape_html("&quot;") == "&amp;quot;"
}

pub fn escape_html_combined_test() {
  assert email.escape_html("<a href=\"x&y\">")
    == "&lt;a href=&quot;x&amp;y&quot;&gt;"
}

pub fn escape_html_no_special_chars_test() {
  assert email.escape_html("hello world") == "hello world"
}

pub fn escape_html_empty_test() {
  assert email.escape_html("") == ""
}

// build_html/2

pub fn build_html_basic_test() {
  let result = email.build_html("some diff", "https://example.com")
  assert string.contains(result, "example.com")
  assert string.contains(result, "some diff")
  assert string.contains(result, "<pre")
}

pub fn build_html_escapes_domain_test() {
  let result = email.build_html("diff", "<script>alert(1)</script>")
  assert !string.contains(result, "<script>")
  assert string.contains(result, "&lt;script&gt;")
}

pub fn build_html_escapes_diff_test() {
  let result = email.build_html("<b>bold</b>", "example.com")
  assert !string.contains(result, "<b>")
  assert string.contains(result, "&lt;b&gt;")
}
