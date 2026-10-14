#!/bin/bash
# 安裝 AFM輸入法並由輸入法程式自行註冊(Squirrel/KeyTao 同款流程)
# 默认用户级 ~/Library/Input Methods(无需 sudo);--system 装系统级(需 sudo)
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d "build/AFM輸入法.app" ] || { echo "先运行 scripts/package.sh"; exit 1; }
"build/AFM輸入法.app/Contents/MacOS/AFMInput" --check-quick

if [ "${1:-}" = "--system" ]; then
    APP="/Library/Input Methods/AFM輸入法.app"
    LEGACY_APP="/Library/Input Methods/AFM拼音.app"
    sudo mkdir -p "$(dirname "$APP")"
    sudo rm -rf "$APP"
    sudo cp -R "build/AFM輸入法.app" "$APP"
    sudo chown -R root:wheel "$APP"
    sudo rm -rf "$LEGACY_APP"
else
    APP="$HOME/Library/Input Methods/AFM輸入法.app"
    LEGACY_APP="$HOME/Library/Input Methods/AFM拼音.app"
    mkdir -p "$(dirname "$APP")"
    rm -rf "$APP"
    cp -R "build/AFM輸入法.app" "$APP"
    rm -rf "$LEGACY_APP"
fi

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
# 注意: 不做任何重签——package.sh 已用 AFM-IME-Dev 证书签名(重签 ad-hoc 会变 DR,
# TCC「输入监控」授权随 cdhash 失效,Shift tap 静默失明,见 AGENTS.md 代码签名一节)

"$APP/Contents/MacOS/AFMInput" --quit 2>/dev/null || true
"$APP/Contents/MacOS/AFMInput" --register-input-source
if "$APP/Contents/MacOS/AFMInput" --enable-input-source; then
    "$APP/Contents/MacOS/AFMInput" --select-input-source || true
    echo "== 安裝完成: $APP =="
else
    echo "== App 已安裝並寫入啟用偏好: $APP =="
    echo "首次安裝或新增速成模式，請儲存工作後自行登出再登入，再執行 scripts/post-login-check.sh。"
fi
