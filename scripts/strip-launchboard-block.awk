# Remove the LaunchBoard marker block from ~/.config/hypr/bindings.lua.
# Fail closed: unbalanced BEGIN/END markers exit 1 and print nothing useful
# for replacement, so callers leave the original file in place.
/BEGIN launchboard/ {
  if (inblock) {
    err = 1
    exit 1
  }
  inblock = 1
  next
}
/END launchboard/ {
  if (!inblock) {
    err = 1
    exit 1
  }
  inblock = 0
  next
}
inblock { next }
{ print }
END {
  if (inblock || err) exit 1
}
