import ciele/diff
import gleam/string

// compute/2

pub fn compute_reports_changed_lines_test() {
  let diff = diff.compute("eorðe\n", "earth\n")
  assert string.contains(diff, "-eorðe")
  assert string.contains(diff, "+earth")
}

pub fn compute_no_change_is_empty_test() {
  assert diff.compute("the\nsame\n", "the\nsame\n") == ""
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
