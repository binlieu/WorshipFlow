# FIX-Q: sourced by the measuring scripts (measure-drags.sh, fixp-run.sh, fixq-run.sh). `measure_build <derived-data> <log>` builds the app and
# prints the path of the built .app. WF_CONFIG=Debug (default) or WF_CONFIG=Release; a Release measuring build is compiled with the WF_MEASURE
# condition, which switches the timing hooks on (they are `#if DEBUG || WF_MEASURE`). The packaged app (package-test-build.sh) never has it.
measure_build() {
  local dd="$1" log="$2" config="${WF_CONFIG:-Debug}"
  local extra=()
  if [ "$config" = "Release" ]; then extra=("SWIFT_ACTIVE_COMPILATION_CONDITIONS=\$(inherited) WF_MEASURE"); fi
  xcodebuild -project WORSHIPFLOW.xcodeproj -scheme WORSHIPFLOW -configuration "$config" -destination 'platform=macOS' \
    -derivedDataPath "$dd" ${extra[@]+"${extra[@]}"} build -quiet > "$log" 2>&1 || { grep -E "error:" "$log" | head -20; return 1; }
  ls -d "$dd"/Build/Products/"$config"/*.app | head -1
}
