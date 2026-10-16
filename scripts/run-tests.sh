#!/bin/bash
# Runs the YAxUnit tests of the extension МгновеннаяОтправкаПисемТесты in the local base.
# Exit codes: 0 — all green, 1 — failures, 2 — the environment is not ready (no result file).
# Base path, user and platform come from .v8-project.json (the "default" base).
# Must run outside the Claude Code sandbox: 1C exits with 134 inside it.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="$ROOT/.v8-project.json"
TEST_EXTENSION="МгновеннаяОтправкаПисемТесты"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-600}"

if [ ! -f "$REGISTRY" ]; then
  echo "Нет $REGISTRY. Создайте его по разделу Tooling в CLAUDE.md." >&2
  exit 2
fi

json() { plutil -extract "$1" raw -o - "$REGISTRY"; }
V8PATH="$(json v8path)"
BASE_PATH="$(json databases.0.path)"
BASE_USER="$(json databases.0.user)"

OUT="$ROOT/.local/tests"
mkdir -p "$OUT"
rm -f "$OUT/exit-code.txt" "$OUT/junit.xml" "$OUT/yaxunit.log" "$OUT/1c.log"

cat > "$OUT/yaxunit.json" <<EOF
{
  "filter": { "extensions": ["$TEST_EXTENSION"] },
  "reportFormat": "jUnit",
  "reportPath": "$OUT/junit.xml",
  "exitCode": "$OUT/exit-code.txt",
  "showReport": false,
  "closeAfterTests": true,
  "logging": { "enable": true, "file": "$OUT/yaxunit.log", "level": "debug" }
}
EOF

"$V8PATH/1cv8c" ENTERPRISE /F"$BASE_PATH" /N"$BASE_USER" \
  /C"RunUnitTests=$OUT/yaxunit.json" \
  /DisableStartupDialogs /DisableStartupMessages /DisableUnrecoverableErrorMessage \
  /UseHwLicenses- /Out"$OUT/1c.log" &
PID=$!

ELAPSED=0
while kill -0 "$PID" 2>/dev/null; do
  if [ "$ELAPSED" -ge "$TIMEOUT_SECONDS" ]; then
    echo "1С не завершилась за $TIMEOUT_SECONDS с, процесс остановлен." >&2
    kill "$PID" 2>/dev/null
    exit 2
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ ! -f "$OUT/exit-code.txt" ]; then
  echo "Нет файла результата: тесты не выполнились. Лог YAxUnit: $OUT/yaxunit.log" >&2
  exit 2
fi

# 1C writes the file with a BOM and CRLF: keep digits only.
CODE="$(LC_ALL=C tr -cd '0-9' < "$OUT/exit-code.txt")"
TESTS=0
if [ -f "$OUT/junit.xml" ]; then
  TESTS="$(grep -o '<testcase ' "$OUT/junit.xml" | wc -l | tr -d ' ')"
  echo "Тестов: $TESTS. Отчёт: $OUT/junit.xml"
fi

# YAxUnit skips a test module that fails to compile and still reports success.
if grep -q '\[ERR\]' "$OUT/yaxunit.log" 2>/dev/null; then
  echo "RED: в журнале YAxUnit есть ошибки (например, тестовый модуль не скомпилировался):"
  grep -A3 '\[ERR\]' "$OUT/yaxunit.log" | head -20
  exit 1
fi
if [ "$TESTS" = "0" ]; then
  echo "RED: не выполнено ни одного теста."
  exit 1
fi

if [ "$CODE" = "0" ]; then
  echo "GREEN"
  exit 0
fi

echo "RED"
if [ -f "$OUT/junit.xml" ]; then
  for N in $(seq 1 "$(xmllint --xpath 'count(//testcase[failure or error])' "$OUT/junit.xml")"); do
    NAME="$(xmllint --xpath "string((//testcase[failure or error])[$N]/@classname)" "$OUT/junit.xml")"
    MESSAGE="$(xmllint --xpath "string((//testcase[failure or error])[$N]/*[self::failure or self::error]/@message)" "$OUT/junit.xml")"
    echo "- $NAME: ${MESSAGE:0:500}"
  done
fi
exit 1
