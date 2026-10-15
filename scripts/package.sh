#!/bin/zsh
# 打包单一产物 build/AFM輸入法.app = 输入法引擎 + 内嵌设置中心(Contents/PlugIns/AFMSettings.app)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

if [ ! -s Data/dict.bin ]; then
  zsh scripts/fetch_pinyin_dict.sh
fi

# 速成词库属于必需资源；缺失时尝试仓库构建器，仍缺失就停止，避免产出不完整安装包。
if [ ! -f Data/quick.json ]; then
  if [ -f scripts/build_quick.py ]; then
    python3 scripts/build_quick.py
  else
    echo "!! 缺少 Data/quick.json，且 scripts/build_quick.py 不存在；无法打包 AFM速成" >&2
    exit 1
  fi
fi
if [ ! -s Data/quick.json ] || ! python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d.get("version")==1 and all(isinstance(d.get(k),dict) for k in ("candidates","fullCandidates","associations","roots"))' Data/quick.json; then
  echo "!! Data/quick.json 缺失、为空或格式不符；无法打包 AFM速成" >&2
  exit 1
fi

# 簽署身份優先序：Developer ID Application、Apple Development、AFM-IME-Dev、ad-hoc。
# 可用 AFM_SIGN_IDENTITY 指定憑證名稱或 SHA-1；AFM_SIGN_TEAM 可限定 Team。
source scripts/signing-identities.sh
SIGN_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
AFM_CERTIFICATE_TEAMS="$(printf '%s\n' "$SIGN_IDENTITIES" | python3 scripts/signing-certificate-teams.py)"
afm_select_app_identity "$SIGN_IDENTITIES" "${AFM_SIGN_IDENTITY:-}" "${AFM_SIGN_TEAM:-}"
SIGN_ID="$AFM_SELECTED_IDENTITY"
SIGN_TEAM="$AFM_SELECTED_TEAM"
SIGN_KIND="$AFM_SELECTED_KIND"

# 构建: xcodebuild(Xcode 工具链 + macOS 27 SDK,部署基线 macOS 26)。
# Xcode 缺失/构建失败时回退 swift build(CLT,SDK 同为 27)。
# 工具链顺序: Xcode-beta.app(27,Swift 6.4)优先——26.x 工具链的 FoundationModels interface 把
# Provider API 藏在 $AsyncExecutionBehaviorAttributes 特性门后,Swift 6.3.3 编不过(kb36 云端通道
# "cannot find type LanguageModel");不动全局 xcode-select(开发机可能并行用 26.x 编其他软件)。
XDEV="${DEVELOPER_DIR:-}"
if [ -z "$XDEV" ]; then
  for c in /Applications/Xcode-beta.app/Contents/Developer /Applications/Xcode.app/Contents/Developer; do
    [ -d "$c" ] && XDEV="$c" && break
  done
fi
BINDIR=""
if [ -n "$XDEV" ] && [ -d "$XDEV" ]; then
  if DEVELOPER_DIR="$XDEV" xcodebuild -scheme afm-ime-Package -configuration Release \
       -destination 'platform=macOS' -derivedDataPath .build/xcode build >/dev/null; then
    BINDIR=".build/xcode/Build/Products/Release"
    echo "构建完成: xcodebuild (macOS 27 SDK, DEVELOPER_DIR=$XDEV)"
  else
    echo "!! xcodebuild 构建失败,回退 swift build(CLT)"
  fi
else
  echo "!! 未找到 Xcode(DEVELOPER_DIR 未设且 /Applications 无 Xcode*.app),回退 swift build(CLT)"
fi
if [ -z "$BINDIR" ]; then
  swift build -c release
  BINDIR="$(swift build -c release --show-bin-path)"
fi

# Metal shader → default.metallib(候选条水滴折射 layerEffect)。
# 需要 Xcode 的 Metal Toolchain(Xcode 26+ 组件缺失时: DEVELOPER_DIR=<Xcode> xcodebuild -downloadComponent metalToolchain);
# 缺失/编译失败则打包照常,水滴退化为纯玻璃无折射。
XDEV="${DEVELOPER_DIR:-}"
if [ -z "$XDEV" ]; then
  for c in /Applications/Xcode-beta.app/Contents/Developer /Applications/Xcode.app/Contents/Developer; do
    [ -d "$c" ] && XDEV="$c" && break
  done
fi
METALLIB=""
if [ -n "$XDEV" ] && [ -d "$XDEV" ]; then
  if DEVELOPER_DIR="$XDEV" xcrun -sdk macosx metal -c Metal/DropletLens.metal -o build/DropletLens.air \
     && DEVELOPER_DIR="$XDEV" xcrun -sdk macosx metallib build/DropletLens.air -o build/default.metallib; then
    METALLIB="build/default.metallib"
    echo "Metal shader 编译完成: default.metallib (DEVELOPER_DIR=$XDEV)"
  else
    echo "!! Metal shader 编译失败——水滴将无折射。需要 Xcode + Metal Toolchain 组件"
  fi
else
  echo "!! 未找到 Xcode(DEVELOPER_DIR 未设且 /Applications 无 Xcode*.app)——跳过 Metal shader,水滴将无折射"
fi

# 图标(单一来源 Data/logo.png,1254² 液态玻璃「拼」设计稿):
#   AppIcon.icns — iconset 多尺寸 → 引擎+helper 双包 CFBundleIconFile(Finder/Launchpad/Dock 生效)
#   icon.tiff    — 16pt 多表示(16px 72dpi + 32px 144dpi,tiffutil 合页)→ 引擎 Resources,
#                  Info.plist tsInputMethodIconFileKey / tsInputMode*IconFileKey 四键引用 =
#                  系统设置输入法列表 + 输入菜单图标
# 坑①:sips 转 PNG 必须显式 -s format png,否则输出仍是 TIFF 内容 iconutil 拒收;
# 坑②:32px 页必须标 144dpi 保持 16pt 表示,否则菜单把选项行高撑成两倍
ICON=""
TISICON=""
if [ -f Data/logo.png ]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256; do
    sips -s format png -z $s $s Data/logo.png --out "$ICONSET/icon_${s}x$s.png" >/dev/null
    d=$((s * 2))
    sips -s format png -z $d $d Data/logo.png --out "$ICONSET/icon_${s}x$s@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns && ICON="build/AppIcon.icns" && rm -rf "$ICONSET"
  [ -z "$ICON" ] && echo "!! AppIcon.icns 生成失败——两包将无 Finder 图标"
  sips -s format tiff -z 16 16 Data/logo.png --out build/icon16.tiff >/dev/null
  sips -s format tiff -z 32 32 Data/logo.png --out build/icon32.tiff >/dev/null
  sips -s dpiHeight 144 -s dpiWidth 144 build/icon32.tiff >/dev/null
  if tiffutil -cat build/icon16.tiff build/icon32.tiff -out build/icon.tiff >/dev/null 2>&1; then
    TISICON="build/icon.tiff"
  fi
  [ -z "$TISICON" ] && echo "!! icon.tiff 生成失败——输入菜单/系统设置将无图标"
fi

# 单一产物: build/AFM輸入法.app = 输入法引擎(部署到 ~/Library/Input Methods/AFM輸入法.app),
# 设置中心作为 helper 嵌在 Contents/PlugIns/AFMSettings.app(经输入法菜单「设置…」打开,
# 顶层只有一个 App 条目,Launchpad/Spotlight 不再出现双 AFM)
APP="build/AFM輸入法.app"
# 清理历史产物(改名/合并后残留的旧 bundle 会被 LaunchServices 索引成幽灵条目)
rm -rf build/AFMInput.app build/AFM拼音安装器.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINDIR/afm-input" "$APP/Contents/MacOS/AFMInput"
cp Data/dict.bin "$APP/Contents/Resources/dict.bin"
cp Data/builtin-user-words.json "$APP/Contents/Resources/builtin-user-words.json"  # 内置用户词种子(UserFreq 首启补种,kb40)
# 原始資料由 mkstemp 生成時是 600；App 裝到系統目錄後，所有使用者都必須能讀取詞庫。
install -m 644 Data/quick.json "$APP/Contents/Resources/quick.json"
[ -n "$METALLIB" ] && cp "$METALLIB" "$APP/Contents/Resources/default.metallib"
[ -n "$TISICON" ] && cp "$TISICON" "$APP/Contents/Resources/icon.tiff"
[ -n "$ICON" ] && cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# 輸入源顯示名:TIS 以輸入源 ID 到 InfoPlist.strings 查名稱；兩種 mode 各有本地化名稱。
# Bundle 名稱由 Info.plist 提供，輸入法選單及系統設定顯示「AFM拼音」和「AFM速成」。
for lproj in zh-Hans zh-Hant en; do
  mkdir -p "$APP/Contents/Resources/$lproj.lproj"
  cat > "$APP/Contents/Resources/$lproj.lproj/InfoPlist.strings" <<'STRINGS'
"moe.bemly.inputmethod.AfmIME" = "AFM輸入法";
"moe.bemly.inputmethod.AfmIME.afmpinyin.hans" = "AFM拼音";
"moe.bemly.inputmethod.AfmIME.afmquick.hant" = "AFM速成";
STRINGS
done

cat > "$APP/Contents/Resources/zh-Hant.lproj/InfoPlist.strings" <<'STRINGS'
"moe.bemly.inputmethod.AfmIME" = "AFM輸入法";
"moe.bemly.inputmethod.AfmIME.afmpinyin.hans" = "AFM拼音";
"moe.bemly.inputmethod.AfmIME.afmquick.hant" = "AFM速成";
STRINGS

cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<'STRINGS'
"moe.bemly.inputmethod.AfmIME" = "AFM Input Method";
"moe.bemly.inputmethod.AfmIME.afmpinyin.hans" = "AFM Pinyin";
"moe.bemly.inputmethod.AfmIME.afmquick.hant" = "AFM Quick";
STRINGS

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>zh-Hant</string>
	<key>CFBundleExecutable</key><string>AFMInput</string>
	<key>CFBundleIdentifier</key><string>moe.bemly.inputmethod.AfmIME</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>CFBundleName</key><string>AFM輸入法</string>
	<key>CFBundleDisplayName</key><string>AFM輸入法</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>2026.10.15.5</string>
	<key>CFBundleVersion</key><string>2026101505</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>LSBackgroundOnly</key><false/>
	<key>LSUIElement</key><true/>
	<key>InputMethodConnectionName</key><string>moe.bemly.inputmethod.AfmIME_Connection</string>
	<key>InputMethodServerControllerClass</key><string>afm_input.InputController</string>
	<key>TISIntendedLanguage</key><string>zh-Hans</string>
	<key>TICapsLockLanguageSwitchCapable</key><true/>
	<key>tsInputMethodCharacterRepertoireKey</key>
	<array><string>Hans</string><string>Hant</string><string>Latn</string></array>
	<key>tsInputMethodIconFileKey</key><string>icon.tiff</string>
	<key>ComponentInputModeDict</key>
	<dict>
		<key>tsInputModeListKey</key>
		<dict>
			<key>moe.bemly.inputmethod.AfmIME.afmpinyin.hans</key>
			<dict>
				<key>TISInputSourceID</key><string>moe.bemly.inputmethod.AfmIME.afmpinyin.hans</string>
				<key>TISIntendedLanguage</key><string>zh-Hans</string>
				<key>tsInputModeMenuIconFileKey</key><string>icon.tiff</string>
				<key>tsInputModeAlternateMenuIconFileKey</key><string>icon.tiff</string>
				<key>tsInputModePaletteIconFileKey</key><string>icon.tiff</string>
				<key>tsInputModeCharacterRepertoireKey</key>
				<array><string>Hans</string><string>Latn</string></array>
				<key>tsInputModeDefaultStateKey</key><false/>
				<key>tsInputModeIsVisibleKey</key><true/>
				<key>tsInputModeKeyEquivalentModifiersKey</key><integer>4608</integer>
				<key>tsInputModePrimaryInScriptKey</key><false/>
				<key>tsInputModeScriptKey</key><string>smUnicodeScript</string>
			</dict>
			<key>moe.bemly.inputmethod.AfmIME.afmquick.hant</key>
			<dict>
				<key>TISInputSourceID</key><string>moe.bemly.inputmethod.AfmIME.afmquick.hant</string>
				<key>TISIntendedLanguage</key><string>zh-Hant</string>
				<key>tsInputModeMenuIconFileKey</key><string>icon.tiff</string>
				<key>tsInputModeAlternateMenuIconFileKey</key><string>icon.tiff</string>
				<key>tsInputModePaletteIconFileKey</key><string>icon.tiff</string>
				<key>tsInputModeCharacterRepertoireKey</key>
				<array><string>Hant</string><string>Latn</string></array>
				<key>tsInputModeDefaultStateKey</key><false/>
				<key>tsInputModeIsVisibleKey</key><true/>
				<key>tsInputModeKeyEquivalentModifiersKey</key><integer>4608</integer>
				<key>tsInputModePrimaryInScriptKey</key><false/>
				<key>tsInputModeScriptKey</key><string>smUnicodeScript</string>
			</dict>
		</dict>
		<key>tsVisibleInputModeOrderedArrayKey</key>
		<array><string>moe.bemly.inputmethod.AfmIME.afmpinyin.hans</string><string>moe.bemly.inputmethod.AfmIME.afmquick.hant</string></array>
	</dict>
</dict>
</plist>
PLIST

# 設定中心 helper:嵌在引擎 bundle Contents/PlugIns/(獨立程序承載 GUI 視窗,引擎本身 LSUIElement
# 無法彈窗；嵌套 bundle 不進 Launchpad／Spotlight 索引，頂層只有「AFM輸入法」一個條目。
# 入口: 输入法菜单「设置…」(InputController.menu) / 未安装态直接打开引擎 bundle 自动拉起。
HELPER="$APP/Contents/PlugIns/AFMSettings.app"
mkdir -p "$HELPER/Contents/MacOS" "$HELPER/Contents/Resources"
cp "$BINDIR/afm-app" "$HELPER/Contents/MacOS/AFMSettings"
cp Data/builtin-user-words.json "$HELPER/Contents/Resources/builtin-user-words.json"  # helper 先启动时也能完成补种
[ -n "$ICON" ] && cp "$ICON" "$HELPER/Contents/Resources/AppIcon.icns"
cat > "$HELPER/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
	<key>CFBundleExecutable</key><string>AFMSettings</string>
	<key>CFBundleIdentifier</key><string>moe.bemly.AFMSettings</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>AFM輸入法</string>
	<key>CFBundleDisplayName</key><string>AFM輸入法</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>2026.10.15.5</string>
	<key>CFBundleVersion</key><string>2026101505</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
</dict>
</plist>
PLIST
# 系統級安裝後檔案會屬於 root；靜態 App 資源須可供一般使用者讀取，目錄及程式須可執行。
chmod -R a+rX "$APP"
SIGN_ARGS=(--force --sign "$SIGN_ID")
if [ "$SIGN_KIND" = developer-id ]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
# 先簽 helper，再簽外層 App；選定憑證後任何簽署或驗證失敗都停止打包。
codesign "${SIGN_ARGS[@]}" "$HELPER"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --strict --verbose=2 "$HELPER"
if [ "$SIGN_ID" = "-" ]; then
  echo "打包完成: $APP (ad-hoc 簽署，內含設置中心 helper)"
else
  echo "打包完成: $APP (簽署身份: $SIGN_ID, Team: ${SIGN_TEAM:-無}, 內含設置中心 helper)"
fi
