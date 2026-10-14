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

if "$BIN" --ensure-enabled; then
  echo "=== 已收錄！啟用兩種模式並選取拼音 ==="
  "$BIN" --select-input-source || true
  open "$APP"
  echo "完成：按 Ctrl+Space 切換至 AFM拼音，輸入 nihao 測試"
  echo "亦可在輸入來源選 AFM速成，輸入 aa 測試。"
else
  echo "=== 登入掃描未收錄 ==="
  echo "重新遞交註冊後再登出及登入："
  echo "  \"$BIN\" --register-input-source"
  exit 1
fi
