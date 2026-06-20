//// Small helpers for normalising the scheme on a domain or URL.

/// Prefix `domain` with `https://` unless it already carries a scheme.
pub fn with_scheme(domain: String) -> String {
  case domain {
    "http://" <> _ | "https://" <> _ -> domain
    _ -> "https://" <> domain
  }
}

/// Strip a leading `http://` or `https://` scheme from `url`.
pub fn without_scheme(url: String) -> String {
  case url {
    "https://" <> rest -> rest
    "http://" <> rest -> rest
    _ -> url
  }
}
