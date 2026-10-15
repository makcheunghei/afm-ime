#!/bin/zsh
# 打包 .pkg 安装器:build/AFM輸入法-<版本>.pkg
#   payload = AFM輸入法.app → /Library/Input Methods(系统级,双击 pkg 管理员授权安装)
#   postinstall 結束舊引擎並更新正式 App 的登記；不自動啟用輸入來源。
#   首次安装需注销重登一次完成 TIS 登录扫描收录;之后更新 = 换盘 + 引擎重启,无需注销
#   簽名: 只使用與 App Team 相同的 Developer ID Installer；沒有時產生 unsigned pkg。
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d "build/AFM輸入法.app" ] || { echo "先运行 scripts/package.sh"; exit 1; }
[ -s "build/AFM輸入法.app/Contents/Resources/quick.json" ] || {
  echo "缺少已打包的速成词库；请先运行 scripts/package.sh" >&2
  exit 1
}
python3 - <<'PY'
from pathlib import Path
import stat, plistlib
app = Path('build/AFM輸入法.app')
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
modes = info['ComponentInputModeDict']['tsInputModeListKey']
assert len(modes) == 2 and len({m['TISInputSourceID'] for m in modes.values()}) == 2, '輸入模式 ID 必須唯一'
assert all(not m.get('tsInputModeDefaultStateKey') for m in modes.values()), '來源須由使用者獨立加入，禁止自動補回'
assert all(not m.get('tsInputModePrimaryInScriptKey') for m in modes.values()), '獨立來源不應強制保留主模式'
for path in [app, *app.rglob('*')]:
    mode = path.stat().st_mode
    if not mode & stat.S_IROTH or path.is_dir() and not mode & stat.S_IXOTH:
        raise SystemExit(f'封包含一般使用者不可存取的檔案：{path}；請重新執行 scripts/package.sh')
for relative in ('Contents/MacOS/AFMInput', 'Contents/PlugIns/AFMSettings.app/Contents/MacOS/AFMSettings'):
    if not (app / relative).stat().st_mode & stat.S_IXOTH:
        raise SystemExit(f'封包程式沒有一般使用者執行權限：{relative}')
PY

VERSION=$(plutil -extract CFBundleShortVersionString raw "build/AFM輸入法.app/Contents/Info.plist")
IDENT="moe.bemly.inputmethod.AfmIME.pkg"
OUT="build/AFM輸入法-$VERSION.pkg"

PACKAGE_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/afm-package.XXXXXX")
PACKAGE_TEMP_NOINDEX="$PACKAGE_TEMP.noindex"
mv "$PACKAGE_TEMP" "$PACKAGE_TEMP_NOINDEX"
trap 'rm -rf "$PACKAGE_TEMP_NOINDEX"' EXIT
PACKAGE_ROOT="$PACKAGE_TEMP_NOINDEX/pkgroot"
PACKAGE_SCRIPTS="$PACKAGE_TEMP_NOINDEX/pkgscripts"
COMPONENT="$PACKAGE_TEMP_NOINDEX/AFM輸入法-component.pkg"
STAGE="$PACKAGE_ROOT/Library/Input Methods"
rm -f "$OUT"
mkdir -p "$STAGE" "$PACKAGE_SCRIPTS"
cp -R "build/AFM輸入法.app" "$STAGE/"

cat > "$PACKAGE_SCRIPTS/postinstall" <<'POST'
#!/bin/bash
# AFM輸入法 安裝後腳本(root 執行):TIS 操作以主控台用戶身份執行(TIS 快取/偏好都是 per-user)
set -u
APP="/Library/Input Methods/AFM輸入法.app"
BIN="$APP/Contents/MacOS/AFMInput"
[ -x "$BIN" ] || { echo "!! 引擎二进制缺失: $BIN"; exit 1; }

# 结束运行中的旧引擎(launchd/imklaunchagent 需要时自动重启,拿到新 bundle)
killall AFMInput 2>/dev/null || true
killall AFMSettings 2>/dev/null || true

# 舊版使用 AFM拼音.app；新 bundle 已安裝後清理舊路徑，讓升級只保留一份。
rm -rf "/Library/Input Methods/AFM拼音.app"

# 更新正式位置的 App 登記，避免系統繼續解析建置副本的舊模式宣告。
# lsregister 更新 App 的位置和描述，不呼叫 TISRegister/TISEnable 或改寫啟用清單。
CONSOLE_USER=$(stat -f%Su /dev/console)
if [ "$CONSOLE_USER" != root ] && [ "$CONSOLE_USER" != loginwindow ]; then
    USER_UID=$(id -u "$CONSOLE_USER")
    launchctl asuser "$USER_UID" sudo -u "$CONSOLE_USER" \
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$APP" || true
fi

echo "AFM輸入法已安裝到 /Library/Input Methods。請在系統設定加入所需的 AFM拼音或 AFM速成；更新不會補回已移除的來源。"
exit 0
POST
chmod +x "$PACKAGE_SCRIPTS/postinstall"

pkgbuild --root "$PACKAGE_ROOT" --scripts "$PACKAGE_SCRIPTS" \
    --identifier "$IDENT" --version "$VERSION" --install-location "/" \
    "$COMPONENT"

# productbuild 先產生 pkg。只能用 Developer ID Installer 簽；明確指定的身份透過
# AFM_INSTALLER_IDENTITY 傳入，並且必須與 App Team 相同。
productbuild --package "$COMPONENT" \
    --product "build/AFM輸入法.app/Contents/Info.plist" \
    "$OUT"
source scripts/signing-identities.sh
SIGN_IDENTITIES="$(security find-identity -v 2>/dev/null || true)"
AFM_CERTIFICATE_TEAMS="$(printf '%s\n' "$SIGN_IDENTITIES" | python3 scripts/signing-certificate-teams.py)"
APP_TEAM="$(codesign -dv --verbose=4 "build/AFM輸入法.app" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
afm_select_installer_identity "$SIGN_IDENTITIES" "$APP_TEAM" "${AFM_INSTALLER_IDENTITY:-}"
INSTALLER_ID="$AFM_SELECTED_INSTALLER"
if [ -n "$INSTALLER_ID" ]; then
  productsign --sign "$INSTALLER_ID" "$OUT" "$OUT.signed"
  mv "$OUT.signed" "$OUT"
  pkgutil --check-signature "$OUT"
  echo "pkg 已使用匹配 App Team 的 Developer ID Installer 簽署: $INSTALLER_ID"
else
  echo "!! 找不到與 App Team (${APP_TEAM:-未知}) 匹配的 Developer ID Installer；已產生 unsigned pkg: $OUT" >&2
fi

echo "打包完成: $OUT"
