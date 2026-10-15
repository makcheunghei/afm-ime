#!/bin/bash
# 登出再登入後執行：使用正式 App 檢查兩個模式，不依賴本地實驗 probe。
set -euo pipefail
APP=""
for CANDIDATE in "$HOME/Library/Input Methods/AFM輸入法.app" "/Library/Input Methods/AFM輸入法.app"; do
  if [ -d "$CANDIDATE" ]; then APP="$CANDIDATE"; break; fi
done
[ -n "$APP" ] || { echo "未安裝 AFM輸入法，請先執行 scripts/install.sh。"; exit 1; }
BIN="$APP/Contents/MacOS/AFMInput"
"$BIN" --status

"$BIN" --check-quick
echo "本檢查不修改輸入來源。請在系統設定加入所需模式，再自行切換測試。"
