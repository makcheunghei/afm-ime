#!/bin/zsh
# 打包 .pkg 安装器:build/AFM輸入法-<版本>.pkg
#   payload = AFM輸入法.app → /Library/Input Methods(系统级,双击 pkg 管理员授权安装)
#   postinstall = 结束运行中的引擎 → 以控制台用户身份递交 TIS 注册(内部查重)+ 幂等启用(--ensure-enabled,
#                 已啟用模式保留原狀，只補齊缺少的模式)
#   首次安装需注销重登一次完成 TIS 登录扫描收录;之后更新 = 换盘 + 引擎重启,无需注销
#   签名: 优先自签证书 AFM-IME-Dev,缺失回退 ad-hoc(对外分发需 Developer ID + 公证,见 AGENTS.md)
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d "build/AFM輸入法.app" ] || { echo "先运行 scripts/package.sh"; exit 1; }
[ -s "build/AFM輸入法.app/Contents/Resources/quick.json" ] || {
  echo "缺少已打包的速成词库；请先运行 scripts/package.sh" >&2
  exit 1
}
python3 - <<'PY'
from pathlib import Path
import stat
app = Path('build/AFM輸入法.app')
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

CONSOLE_USER=$(stat -f%Su /dev/console)
USER_UID=$(id -u "$CONSOLE_USER")
asuser() { launchctl asuser "$USER_UID" sudo -u "$CONSOLE_USER" "$@"; }

echo "== TIS 注册(内部查重,已注册自动跳过) =="
asuser "$BIN" --register-input-source || true
echo "== 启用(幂等:已启用跳过不碰活视图,未启用 defaults 直写兜底) =="
asuser "$BIN" --ensure-enabled || true

echo "AFM輸入法已安裝到 /Library/Input Methods。首次安裝請登出再登入一次完成收錄；之後更新無需登出。"
exit 0
POST
chmod +x "$PACKAGE_SCRIPTS/postinstall"

pkgbuild --root "$PACKAGE_ROOT" --scripts "$PACKAGE_SCRIPTS" \
    --identifier "$IDENT" --version "$VERSION" --install-location "/" \
    "$COMPONENT"

SIGN_ID="AFM-IME-Dev"
security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID" || SIGN_ID="-"
# 签名: productbuild --sign / productsign 要求「installer 签名身份」——自签应用证书(AFM-IME-Dev,
# EKU=codeSigning)会被拒(实测 2026-09-15);codesign 直接签 flat pkg 是假成功(pkgutil 仍报无签名)。
# 故 productbuild 先出未签名 product,再试 productsign,失败则保持未签名
# (本机 sudo installer 可装;对外分发需 Developer ID Installer + 公证)
productbuild --package "$COMPONENT" \
    --product "build/AFM輸入法.app/Contents/Info.plist" \
    "$OUT"
if [ "$SIGN_ID" != "-" ] && productsign --sign "$SIGN_ID" "$OUT" "$OUT.signed" 2>/dev/null; then
  mv "$OUT.signed" "$OUT"
  echo "pkg 已签名: $SIGN_ID"
else
  rm -f "$OUT.signed"
  echo "!! pkg 未签名(自签证书不被 productsign 接受)——本机可用 sudo installer 安装"
fi

echo "打包完成: $OUT (pkg 签名: $([ "$SIGN_ID" != "-" ] && pkgutil --check-signature "$OUT" 2>/dev/null | grep -q "Status: signed" && echo "$SIGN_ID" || echo "无"))"
