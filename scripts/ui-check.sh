#!/bin/bash
# Checks the instant-send UI in the local base through the 1C test client, without a person clicking.
# Builds tools/ui-check into .local/ui-check/, starts a test client (/TESTCLIENT) and runs the scenario
# in a test manager (/TESTMANAGER /Execute) once per stage: with Mailpit running ("ok"), stopped ("down")
# and a reply with a quote that returned to drafts and is sent again ("quote", Mailpit running).
# Prints what the user would see (windows and their texts), letter states, event log errors
# and the letters that reached Mailpit. Usage: scripts/ui-check.sh [ok|down|quote ...] (default: ok down quote).
# Must run outside the Claude Code sandbox: 1C exits with 134 inside it.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="$ROOT/.v8-project.json"
SKILLS="$ROOT/.claude/skills"
OUT="$ROOT/.local/ui-check"
EPF="$OUT/моп_ПроверкаИнтерфейса.epf"
PORT="${PORT:-48111}"
cd "$ROOT"

json() { plutil -extract "$1" raw -o - "$REGISTRY"; }
V8PATH="$(json v8path)"
BASE_PATH="$(json databases.0.path)"
BASE_USER="$(json databases.0.user)"

if [ "$#" -eq 0 ]; then
  set -- ok down quote
fi

mkdir -p "$OUT"
python3 "$SKILLS/epf-build/scripts/epf-build.py" -InfoBasePath "$BASE_PATH" -UserName "$BASE_USER" \
  -SourceFile tools/ui-check/моп_ПроверкаИнтерфейса.xml -OutputFile "$EPF" -ConfigSrc .local/ka-config || exit 2

COMMON=(ENTERPRISE /F"$BASE_PATH" /N"$BASE_USER" /DisableStartupDialogs /DisableStartupMessages
  /DisableUnrecoverableErrorMessage /UseHwLicenses-)

"$V8PATH/1cv8c" "${COMMON[@]}" /TESTCLIENT -TPort"$PORT" /Out"$OUT/client.log" &
CLIENT=$!
trap 'kill "$CLIENT" 2>/dev/null' EXIT

for STAGE in "$@"; do
  if [ "$STAGE" = "down" ]; then
    scripts/mailpit.sh stop >/dev/null
  else
    scripts/mailpit.sh start >/dev/null
  fi
  LOG="$OUT/$STAGE.log"
  rm -f "$LOG"
  "$V8PATH/1cv8c" "${COMMON[@]}" /TESTMANAGER /Execute"$EPF" /C"$LOG;$PORT;$STAGE" /Out"$OUT/manager-$STAGE.log" &
  MANAGER=$!
  ELAPSED=0
  while kill -0 "$MANAGER" 2>/dev/null; do
    if [ "$ELAPSED" -ge 400 ]; then
      echo "Менеджер тестирования не завершился за 400 с, процесс остановлен." >&2
      kill "$MANAGER" 2>/dev/null
      break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
  done
  echo "===== Этап $STAGE"
  cat "$LOG" 2>/dev/null || echo "Нет журнала $LOG. Вывод 1С: $(cat "$OUT/manager-$STAGE.log" 2>/dev/null)"
done

scripts/mailpit.sh start >/dev/null
echo "===== Письма UI-проверки в Mailpit"
curl -s "http://127.0.0.1:8025/api/v1/messages?limit=50" | python3 -c '
import json, sys
for m in json.load(sys.stdin).get("messages", []):
    if any(t.get("Address") == "ui-check@test.local" for t in m.get("To", [])):
        print(m.get("Created", "")[:19], "|", m.get("Subject") or "(пустая тема)")
'

echo "===== Цитата в ответе этапа quote"
curl -s "http://127.0.0.1:8025/api/v1/messages?limit=50" | python3 -c '
import json, sys, urllib.request
for m in json.load(sys.stdin).get("messages", []):
    if m.get("Subject") == "UI-проверка 6: ответ":
        with urllib.request.urlopen("http://127.0.0.1:8025/api/v1/message/" + m["ID"]) as r:
            text = json.load(r).get("Text", "")
        print(m.get("Created", "")[:19], "| маркер UI-ЦИТАТА-6 в тексте:", text.count("UI-ЦИТАТА-6"), "раз (ожидается 1)")
        break
else:
    print("Письмо «UI-проверка 6: ответ» в Mailpit не найдено")
'
