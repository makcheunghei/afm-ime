#!/bin/zsh
# 從基礎專案的固定發行版提取完整拼音詞庫；只展開封包，不執行安裝器。
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -s Data/dict.bin ]; then
  echo "Data/dict.bin 已存在，保留本地詞庫"
  exit 0
fi
mkdir -p .build/upstream Data
PINYIN_PACKAGE=".build/upstream/AFM-Pinyin-2026.09.15.pkg"
PINYIN_UNPACKED=".build/upstream/unpacked"
if [ ! -f "$PINYIN_PACKAGE" ]; then
  curl --fail --location --retry 2 --output "$PINYIN_PACKAGE" \
    https://github.com/Bemly/afm-ime/releases/download/v2026.09.15/AFM-Pinyin-2026.09.15.pkg
fi
python3 - "$PINYIN_PACKAGE" <<'PY'
import hashlib, sys
from pathlib import Path
expected = 'ad9ea7583ae48d39e9d0b590104ea20de18cf6a175620ce190f7a8fc1125c201'
if hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest() != expected:
    raise SystemExit('上游封包 SHA-256 不符，停止提取')
PY
if [ ! -d "$PINYIN_UNPACKED" ]; then
  pkgutil --expand-full "$PINYIN_PACKAGE" "$PINYIN_UNPACKED"
fi
python3 - "$PINYIN_UNPACKED" <<'PY'
import hashlib, os, shutil, struct, sys
from pathlib import Path
source = Path(sys.argv[1]) / 'AFM拼音-component.pkg/Payload/Library/Input Methods/AFM拼音.app/Contents/Resources/dict.bin'
expected = '23acf4058e2708441842386b38c03e78ed0e461b7fea919f029f2ebc3560aecf'
if hashlib.sha256(source.read_bytes()).hexdigest() != expected:
    raise SystemExit('拼音詞庫 SHA-256 不符，停止提取')
with source.open('rb') as f:
    header = f.read(40)
if struct.unpack_from('<II', header) != (0x444D4641, 1):
    raise SystemExit('拼音詞庫格式不符')
target = Path('Data/dict.bin')
temp = target.with_suffix('.bin.tmp')
shutil.copyfile(source, temp)
os.replace(temp, target)
print('完整拼音詞庫已保存：6,986,530 筆')
PY
