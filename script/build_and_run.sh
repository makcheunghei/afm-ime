#!/bin/bash
# Run 只啟動新建置的設定中心；輸入法引擎仍由系統從正式安裝位置管理。
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  run|--verify|--debug|--logs|--telemetry) ;;
  *) echo "usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
HELPER="$ROOT_DIR/build/AFM輸入法.app/Contents/PlugIns/AFMSettings.app"
BINARY="$HELPER/Contents/MacOS/AFMSettings"

# 不結束 AFMInput、不登記建置副本，避免干擾日常打字及輸入來源清單。
/usr/bin/pkill -x AFMSettings 2>/dev/null || true
for attempt in {1..30}; do
  /usr/bin/pgrep -x AFMSettings >/dev/null || break
  /bin/sleep 0.1
done
if /usr/bin/pgrep -x AFMSettings >/dev/null; then
  echo "設定中心尚未結束，停止建置以保留現有執行狀態。" >&2
  exit 1
fi

/bin/zsh scripts/package.sh
test -x "$BINARY"
/usr/bin/open -n "$HELPER"

case "$MODE" in
  --verify|--debug)
    APP_PID=""
    for attempt in {1..50}; do
      APP_PID="$(/usr/bin/pgrep -x AFMSettings | /usr/bin/head -n 1 || true)"
      if [ -n "$APP_PID" ]; then break; fi
      /bin/sleep 0.1
    done
    test -n "$APP_PID" || { echo "設定中心未能啟動。" >&2; exit 1; }
    RUNNING_BINARY="$(/bin/ps -p "$APP_PID" -o comm=)"
    [ "$RUNNING_BINARY" = "$BINARY" ] || {
      echo "執行中的設定中心並非本次建置。" >&2
      exit 1
    }
    echo "已啟動本次建置的設定中心 (PID $APP_PID)。"
    if [ "$MODE" = --debug ]; then /usr/bin/xcrun lldb -p "$APP_PID"; fi
    ;;
  --logs|--telemetry)
    /usr/bin/log stream --info --style compact --predicate 'process == "AFMSettings"'
    ;;
esac
