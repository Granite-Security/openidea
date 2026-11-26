[split("\n")[] | fromjson? | objects] as $events
| [$events[] | select(
    .reason == "compiler-artifact" and .manifest_path == $manifest
    and .target.name == "openidea" and .target.kind == ["bin"]
  ) | select(.executable | type == "string")] | unique_by(.executable)
| if length == 0 then null
  elif length > 1 then error("Cargo reported multiple OpenIDEA release executables")
  else .[0] as $binary
    | [$events[] | select(.reason == "build-script-executed" and .package_id == $binary.package_id)
      | .out_dir | strings] | unique
    | if length == 1 then {executable: $binary.executable, out_dir: .[0]}
      else error("Expected exactly one OpenIDEA build-script OUT_DIR from Cargo") end
  end
