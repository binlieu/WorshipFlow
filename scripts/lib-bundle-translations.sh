# FIX-AC (LIB-004d): sourced by package-test-build.sh. The packaged test build carries the King James Version and nothing else from Bibles/.
# Bibles/ is git-ignored and holds translation files on the owner's Mac only; some are under copyright and must never reach a build, so the
# copy is an allow-list by exact file name (one entry) and the finished app is checked again. Nothing here reads or prints a file's contents.
BUNDLED_TRANSLATIONS=("KJV.json")

# bundle_translations <bibles-folder> <app>: copies each allowed file that exists into <app>/Contents/Resources/Bibles/. Prints one line when
# nothing was copied. Returns 0 either way (a build without the file is a valid build).
bundle_translations() {
  local bibles="$1" app="$2" name copied=0
  for name in "${BUNDLED_TRANSLATIONS[@]}"; do
    if [ -f "$bibles/$name" ] && [ ! -L "$bibles/$name" ]; then
      mkdir -p "$app/Contents/Resources/Bibles"
      cp "$bibles/$name" "$app/Contents/Resources/Bibles/$name"
      copied=1
    fi
  done
  if [ "$copied" = 0 ]; then echo "No Bibles/KJV.json on this Mac: the app is built without a bundled translation."; fi
  return 0
}

# check_bundled_translations <app>: fails (status 1) when <app>/Contents/Resources/Bibles holds anything but the allowed names. Absent is fine.
check_bundled_translations() {
  local dir="$1/Contents/Resources/Bibles" entry name allowed ok
  [ -e "$dir" ] || return 0
  while IFS= read -r entry; do
    ok=0
    for allowed in "${BUNDLED_TRANSLATIONS[@]}"; do [ "$entry" = "$allowed" ] && ok=1; done
    if [ "$ok" = 0 ]; then echo "The app's Resources/Bibles holds an entry that is not on the allow-list: $entry" >&2; return 1; fi
  done < <(ls -A "$dir")
  return 0
}
