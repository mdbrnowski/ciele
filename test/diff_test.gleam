import ciele/config
import ciele/diff
import gleam/string

// handle_diff/4 (dry run)

pub fn handle_diff_dry_run_test() {
  let config =
    config.Config(
      email_address: "to@example.com",
      sender_email_address: "ciele@example.com",
      domains: [],
      dry_run: True,
    )

  // In dry-run mode the whole pipeline (temp files, `diff`, console logging)
  // runs without needing an API key or making any network call.
  assert diff.handle_diff("old\n", "new\n", "example.com", config) == Nil
}

// temp_files/0

pub fn temp_files_returns_two_paths_test() {
  let #(old, new) = diff.temp_files()
  assert old != new
}

pub fn temp_files_unique_test() {
  let #(old1, new1) = diff.temp_files()
  let #(old2, new2) = diff.temp_files()
  assert old1 != old2
  assert new1 != new2
}

pub fn temp_files_contain_ciele_prefix_test() {
  let #(old, new) = diff.temp_files()
  assert string.contains(old, "ciele_old_")
  assert string.contains(new, "ciele_new_")
}
