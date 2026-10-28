import ciele/config.{Page}

/// A minimal config file monitoring the given `domains` array.
fn source(domains: String) -> String {
  "email_address = \"a@b.c\"\nsender_email_address = \"d@e.f\"\ndomains = "
  <> domains
}

// parse/1

pub fn parse_bare_url_test() {
  let assert Ok(config) = config.parse(source("[\"gleam.run\"]"))
  assert config.pages
    == [Page(url: "gleam.run", ignore: [], ignore_attributes: [])]
  assert config.warnings == []
}

pub fn parse_ignore_attributes_test() {
  let assert Ok(config) =
    config.parse(source(
      "[{ url = \"gleam.run\", ignore_attributes = [\"id\"] }]",
    ))
  assert config.pages
    == [Page(url: "gleam.run", ignore: [], ignore_attributes: ["id"])]
  assert config.warnings == []
}

pub fn parse_invalid_ignore_attributes_test() {
  assert config.parse(source(
      "[{ url = \"gleam.run\", ignore_attributes = \"id\" }]",
    ))
    == Error(config.InvalidField("ignore_attributes"))
}

pub fn parse_deprecated_ignore_classes_test() {
  let assert Ok(config) =
    config.parse(source(
      "[{ url = \"gleam.run\", ignore_classes = true, ignore_attributes = [\"id\"] }]",
    ))
  assert config.pages
    == [Page(url: "gleam.run", ignore: [], ignore_attributes: ["class", "id"])]
  assert config.warnings
    == [
      "'ignore_classes' (for gleam.run) is deprecated, use 'ignore_attributes' instead",
    ]
}

pub fn parse_deprecated_ignore_classes_false_test() {
  let assert Ok(config) =
    config.parse(source("[{ url = \"gleam.run\", ignore_classes = false }]"))
  assert config.pages
    == [Page(url: "gleam.run", ignore: [], ignore_attributes: [])]
  assert config.warnings
    == [
      "'ignore_classes' (for gleam.run) is deprecated, use 'ignore_attributes' instead",
    ]
}
