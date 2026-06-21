//// Computing a unified diff between two versions of a page.

import envoy
import filepath
import gleam/erlang/atom.{type Atom}
import gleam/int
import shellout
import simplifile

/// Compute the unified diff between `old` and `new`.
pub fn compute(old: String, new: String) -> String {
  let #(old_path, new_path) = temp_files()

  let _ = simplifile.write(to: old_path, contents: old)
  let _ = simplifile.write(to: new_path, contents: new)

  let diff = run_diff(old_path, new_path)

  let _ = simplifile.delete(old_path)
  let _ = simplifile.delete(new_path)

  diff
}

fn run_diff(old_path: String, new_path: String) -> String {
  case
    shellout.command(
      run: "diff",
      with: ["-u", "--label", "old", "--label", "new", old_path, new_path],
      in: ".",
      opt: [],
    )
  {
    Ok(output) -> output
    Error(#(_status, output)) -> output
  }
}

/// Build a pair of unique temporary file paths for the two versions.
pub fn temp_files() -> #(String, String) {
  let suffix = int.to_string(unique_integer([atom.create("positive")]))
  let tmp_dir = case envoy.get("TMPDIR") {
    Ok(dir) -> dir
    Error(_) -> "/tmp"
  }
  #(
    filepath.join(tmp_dir, "ciele_old_" <> suffix <> ".tmp"),
    filepath.join(tmp_dir, "ciele_new_" <> suffix <> ".tmp"),
  )
}

@external(erlang, "erlang", "unique_integer")
fn unique_integer(options: List(Atom)) -> Int
