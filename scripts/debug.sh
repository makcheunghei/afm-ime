#!/bin/bash
# Debug 模式开关:创建标志文件后由系统按需拉起输入法(launchd),日志实时跟踪
# 用法: scripts/debug.sh        — 开启 debug + 重启输入法 + tail 日志
#       scripts/debug.sh --stop — 关闭 debug + 停止输入法
# 日志: /tmp/afm-ime.log
set -euo pipefail
cd "$(dirname "$0")/.."

LOG="${AFM_LOG:-/tmp/afm-ime.log}"
FLAG=/tmp/afm-ime-debug

killall AFMInput 2>/dev/null || true

if [[ "${1:-}" == "--stop" ]]; then
  rm -f "$FLAG"
  echo "debug 已关闭,输入法已停止(打字或切换输入法时系统会自动拉起)"
  exit 0
fi

touch "$FLAG"
if [ -f "$LOG" ]; then
  LOG_ARCHIVE=$(mktemp "${LOG}.previous.XXXXXX")
  mv "$LOG" "$LOG_ARCHIVE"
fi
touch "$LOG"

# 让系统重新拉起(launchd 管理,别手动 nohup——手动进程客户端连不上)
APP="$HOME/Library/Input Methods/AFM輸入法.app"
[ -d "$APP" ] || APP="/Library/Input Methods/AFM輸入法.app"
[ -d "$APP" ] || { echo "請先安裝 AFM輸入法。"; exit 1; }
open "$APP" 2>/dev/null || true
sleep 1
echo "AFM輸入法 debug 已開啟(PID $(pgrep -x AFMInput | head -1)) 日誌: $LOG"
echo "若切換輸入來源後仍無日誌，切到 ABC 再切回 AFM拼音／AFM速成觸發重連"
echo "================================================"
tail -f "$LOG"
