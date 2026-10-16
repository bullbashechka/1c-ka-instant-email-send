#!/bin/bash
# Local mail trap for ka-demo: Mailpit on the Mac with the settings of TASKS.md 7.0.
# Usage: scripts/mailpit.sh start|stop|status
# Data lives in .local/mailpit (git-ignored). Mail accounts in ka-demo use 127.0.0.1:
# SMTP 1025, POP3 1110, no encryption. Web UI: http://127.0.0.1:8025.
# Nothing is relayed outside; only recipients @test.local are accepted.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/.local/mailpit"
AUTH="$DIR/auth.txt"
PIDFILE="$DIR/mailpit.pid"
LOG="$DIR/mailpit.log"
WEB="127.0.0.1:8025"
SMTP="127.0.0.1:1025"
POP3="127.0.0.1:1110"
RECIPIENTS='(?i)^[^@]+@test\.local$'

running_pid() {
  [ -f "$PIDFILE" ] || return 1
  local pid
  pid="$(tr -cd '0-9' < "$PIDFILE")"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o comm= | grep -q mailpit || return 1
  echo "$pid"
}

message_count() {
  curl -s --max-time 3 "http://$WEB/api/v1/messages?limit=1" |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["total"])' 2>/dev/null
}

start() {
  local pid
  if pid="$(running_pid)"; then
    echo "Mailpit уже работает (pid $pid): http://$WEB"
    return 0
  fi
  if ! command -v mailpit >/dev/null; then
    echo "Mailpit не установлен: brew install mailpit" >&2
    return 2
  fi
  if [ ! -f "$AUTH" ]; then
    echo "Нет $AUTH. Создайте его: одна строка «логин:пароль» для SMTP и POP3." >&2
    return 2
  fi
  mkdir -p "$DIR"
  nohup mailpit \
    --database "$DIR/mailpit.db" --max 5000 \
    --listen "$WEB" --smtp "$SMTP" --pop3 "$POP3" \
    --smtp-auth-file "$AUTH" --smtp-auth-allow-insecure --pop3-auth-file "$AUTH" \
    --smtp-allowed-recipients "$RECIPIENTS" \
    --label ka-demo >> "$LOG" 2>&1 &
  echo $! > "$PIDFILE"
  for _ in $(seq 1 20); do
    if nc -z 127.0.0.1 1025 2>/dev/null && nc -z 127.0.0.1 1110 2>/dev/null; then
      echo "Mailpit запущен (pid $(cat "$PIDFILE")): http://$WEB"
      return 0
    fi
    sleep 0.5
  done
  echo "Mailpit не открыл порты за 10 с. Журнал: $LOG" >&2
  tail -5 "$LOG" >&2
  return 1
}

stop() {
  local pid
  if ! pid="$(running_pid)"; then
    echo "Mailpit не запущен."
    rm -f "$PIDFILE"
    return 0
  fi
  kill "$pid"
  for _ in $(seq 1 20); do
    if ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$PIDFILE"
      echo "Mailpit остановлен."
      return 0
    fi
    sleep 0.5
  done
  echo "Mailpit (pid $pid) не завершился за 10 с." >&2
  return 1
}

status() {
  local pid
  if pid="$(running_pid)"; then
    echo "Mailpit работает (pid $pid): http://$WEB, писем в ловушке: $(message_count)"
  else
    echo "Mailpit не запущен."
    return 1
  fi
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  *) echo "Использование: $0 start|stop|status" >&2; exit 2 ;;
esac
