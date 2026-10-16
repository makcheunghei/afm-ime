#!/bin/zsh
# CLT 27 的 Swift Testing framework 位於新的目錄；native SPM 需要明確傳入。
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_FLAGS=(--build-system native --disable-xctest --enable-swift-testing)
# 背景驗證不建立可見面板，不影響使用者正在進行的輸入。
if [[ "${1:-}" == "--background" ]]; then
  TEST_FLAGS+=(--skip CandidateWindowTests)
  shift
fi
SELECTED_DEV="${DEVELOPER_DIR:-$(xcode-select -p)}"
for TEST_FRAMEWORK_DIR in "$SELECTED_DEV/Library/Developer/Frameworks" "$SELECTED_DEV/Library/Frameworks"; do
  if [ -d "$TEST_FRAMEWORK_DIR/Testing.framework" ]; then
    TEST_FLAGS+=(-Xswiftc -F -Xswiftc "$TEST_FRAMEWORK_DIR" -Xlinker -F -Xlinker "$TEST_FRAMEWORK_DIR" -Xlinker -rpath -Xlinker "$TEST_FRAMEWORK_DIR")
    break
  fi
done
swift test "${TEST_FLAGS[@]}" "$@"
