# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

`PRD.md` (in Russian) is the source of truth. «Ф1»…«Ф9» refer to its features and «П1»…«П29» to its acceptance scenarios; `TASKS.md` tracks the stages. Both extensions are implemented in `src/` and built into `build/*.cfe`; YAxUnit tests were green in `ka-demo`. Development, YAxUnit tests and the build stay in the local file base `ka-demo`: what remains for us is the local setup (task 0.2), reviewing stages 1–5 one by one, the build and install check, and fixing defects from acceptance. Acceptance (stage 7) is done by the company programmer in the client-server base `elektron_ka` on the office server `gemsrvr`; we don't run tests or scenarios there.

The PRD deliberately departs from the director's original ТЗ: sending is asynchronous (background job, up to 3 attempts with pauses 0/10/30 s, user notifications), and the «Отправить сейчас» button is shown for letters in «Исходящие» in client-server bases too. Don't "restore" the ТЗ behavior.

All user-facing texts (notifications, error messages, refusal texts from `ДоступностьОтправки`) must match `PRD.md` word for word.

## Working on a stage

Every `TASKS.md` stage or task goes through three steps. Each step is agreed with the user before the next one starts:

1. **Edge cases.** List the pitfalls of the stage as numbered edge cases, each with options and the recommended one first. The user is not a programmer: they decide only what affects the product and the user experience. Technical choices are ours; state them with the reason. Only read-only checks (code, `.local/ka-config`, reads through the `1c` MCP) are allowed in this step.
2. **Implementation plan.** Write a plan from the agreed edge cases and wait for the user to approve it.
3. **Implementation.** Carry out the approved plan.

The user's «ок» closes the current step only; it never means "go implement". Until the plan is approved, don't install software, change data in a base, load extensions, edit `src/` or start the stand.

## Stack

Strictly BSL (1C:Enterprise) in configuration extensions for «Комплексная автоматизация для Казахстана» ред. 2, version 2.4.5.21, БСП 3.1.7.382. Production is a client-server base. Python and PowerShell are used only by the vendored skill tooling.

Deliverables (per PRD «Результат работ»):

- `src/МгновеннаяОтправкаПисем/`: the product extension, hierarchical Designer XML dump. AddOn, prefix `моп_`, `Version8_3_21`, safe mode off, unsafe-action protection on.
- `src/МгновеннаяОтправкаПисемТесты/`: the YAxUnit test extension. AddOn, prefix `мопТ_`, `Version8_3_21`, safe mode off. Installed only in test bases, never in production.
- `build/<Name>.cfe` for both.

## Architecture

Clicking «Отправить» in the outgoing-email form no longer drops the letter into «Исходящие» for the scheduled job «Получение и отправка электронных писем». Instead, the form writes the letter, starts a background job that sends it, and closes immediately. A client handler waits for the job and shows the result.

- **Borrowed objects:** only `Документ.ЭлектронноеПисьмоИсходящее` and its `ФормаДокумента`, plus what the form references and the extension can't load without: the journal `Взаимодействия`, the picture `КоллекцияПиктограммФайлов`, the enum `ВариантыВажностиВзаимодействия`, the catalog `Пользователи` and 8 document attributes (listed in PRD). Everything else in KA (common modules `УправлениеЭлектроннойПочтой`, `Взаимодействия`, `РаботаСПочтовымиСообщениями`, `ДлительныеОперации`, registers `ЗаблокированныеДляПолученияУчетныеЗаписи` and `НепринятыеКОбработкеПочтовымСерверомИсходящиеПисьма`) is called from extension code without borrowing.
- **Interception style:** `&Перед`, `&После`, `&Вместо` with `ПродолжитьВызов()`. Never `&ИзменениеИКонтроль`.
- **`моп_МгновеннаяОтправкаПисем`** (server common module):
  - `ДоступностьОтправки` is a pure function with no DB access. It holds the send-availability rules, so it is the main unit-test target.
  - **No double send by hiding.** The scheduled job and «Отправить и получить почту» pick letters in one query up front, never re-check status, and unlock the account before writing results. So instead of waiting for them, instant send hides the letter: `ДатаКогдаОтправить = now + 10 min` while sending (both KA queries skip future «Когда отправить»), renewed when less than 5 min is left, cleared in the same write as the outcome. A draft gets the mark in the same write that makes it «Исходящее» (form `&После("ПередЗаписьюНаСервере")`). Only «Отправить сейчас» on a letter that was already «Исходящее» waits for jobs that started before the mark.
  - Account locking reuses the KA register `ЗаблокированныеДляПолученияУчетныеЗаписи` with the 60-minute rule of `УправлениеЭлектроннойПочтой.ЗаблокироватьУчетнуюЗапись`, but a young record only counts while a possible holder is alive (scheduled job, the user command, or an earlier instant send for the same account; job description «Мгновенная отправка письма (<account UUID>)»). In a file base the record always counts. Release deletes the record only if `ДатаБлокировки` is still ours.
  - `НачатьОтправку` deduplicates by the background-job key `"моп_ОтправкаПисьма_" + УникальныйИдентификатор`, clears the scheduled job's rejection record for the letter, hides an «Исходящее» letter, then starts `ОтправитьПисьмоВФоне` through `ДлительныеОперации.ВыполнитьВФоне`.
  - The temp storage for the result is not bound to the form, because the form closes right after the start. The client handler deletes it.
- **`моп_МгновеннаяОтправкаПисемКлиент`** (client common module) waits through `ДлительныеОперацииКлиент.ОжидатьЗавершение` without an owner form and shows notifications per the Ф3 table.
- **Borrowed `ФормаДокумента`:** `&Вместо("ОтправитьПисьмоКлиент")` holds the branching for Черновик/Исходящее × available/not available. `&После` handlers on `ОпределитьВидимостьДоступностьЭлементовВЗависимостиОтСтатусаПисьма` and `УправлениеДоступностью` control the «Отправить сейчас» button.

### KA behaviors that are easy to get wrong (verified against the dump, see PRD)

- For an existing letter, the standard `ПриЧтенииНаСервере` calls `ОпределитьВидимостьДоступностьЭлементовВЗависимостиОтСтатусаПисьма` **before** `ПриСозданииНаСервере`. Form attributes it needs must be filled inside the `&После` of that procedure, not in `ПриСозданииНаСервере`.
- If availability fails for an «Исходящее» letter, don't call `ПродолжитьВызов()`. Otherwise the standard code sets `ОтправлятьСообщенияСразу = Истина` and sends synchronously.
- The standard write adds the quoted original text only for a «Черновик» (`НеобходимаОбработкаПисьмаОснования`), so writing an «Исходящее» letter again doesn't repeat it. We still write an «Исходящее» letter only when it is modified.
- The standard save question («Отправить / Отправить и сохранить») is asked in `ОтправитьВыполнить` before `ОтправитьПисьмоКлиент`, by the account setting. The answer is written into the letter (`УдалятьПослеОтправки`) together with the hide mark, and the background job reads it from the letter.
- `ОбработатьОшибкуОтправкиПисьма` doesn't change the letter status and logs by itself: returning to drafts is ours, don't log rejected recipients twice.
- In BSP debug mode `ДлительныеОперации.ВыполнитьВФоне` runs synchronously even with `ЗапуститьВФоне`; no pauses or waits are possible there.
- The standard `ПередЗаписьюНаСервере` appends the quoted original text on every send-write of a «Черновик» (`ВыполняетсяОтправка` and `ВключатьТелоИсходногоПисьма`), and nothing clears the flag. So `ВернутьВЧерновики` clears `ВключатьТелоИсходногоПисьма`, or the next «Отправить» quotes twice.
- Use `КраткоеПредставлениеОшибки` for users and `ПодробноеПредставлениеОшибки` for the event log. Never use `РасширенноеПредставлениеОшибки`: it downloads error descriptions from the internet on each call.
- The account is released only after the result is written, unlike in the scheduled job.

Before assuming how standard code behaves, check it in `.local/ka-config` (see below) or in the live base through the `1c` MCP server.

## Tooling

### Local setup (all git-ignored)

- **`.local/ka-config/`** is the full KA configuration XML dump (~5.5 GB, ~80 000 files) and the `configSrc` for validation. Search it with `grep -r`/`find` on specific paths; never read or glob it wholesale. The outgoing-letter document is at `.local/ka-config/Documents/ЭлектронноеПисьмоИсходящее/`.
- **`.v8-project.json`** is the `db-list` registry: platform `/opt/1cv8/8.3.23.2040`, base `ka-demo`, which is the file base `~/Documents/1C/Базы/КА демо`, and both extensions mapped to `src/`. It holds credentials, so don't print it or commit it.

### The shared dev base

`ka-demo` is the same file base the sibling project `../b24-task-timesheet` uses. It also has the extensions `Б24ПрототипЭтап1`, `Б24ТабельИзЗадачи`, `Б24ТабельИзЗадачиТесты` and `YAXUNIT` (25.12).

- Never modify, reload or delete those extensions. Always pass `-Extension <Name>` to load scripts and never `-AllExtensions`.
- The scheduled email job is disabled in this base.
- Mail goes to a local Mailpit trap: `scripts/mailpit.sh start|stop|status`, web UI http://127.0.0.1:8025. It accepts only recipients `@test.local` and relays nothing outside. The accounts «Тест с сохранением» and «Тест без сохранения» connect to `127.0.0.1` (SMTP 1025, POP3 1110, no encryption). Mailpit listens on IPv4 only, so the accounts use `127.0.0.1`, not `localhost`.
- It is a file base, so client-server behavior (the PRD's acceptance target) can't be verified locally; the programmer's acceptance on `gemsrvr` covers it.

### MCP servers (`.mcp.json`)

- **`1c`**, at `http://127.0.0.1:6003/mcp`, gives live access to `ka-demo`: queries, metadata, code execution, the event log and BSL syntax help.
  - It is served by `tools/MCP_Toolkit_macos.epf`, which must be open in 1C:Enterprise with the server started. If `mcp__1c__*` calls fail, it isn't running.
  - Read-only checks are fine. Ask before changing data.
  - The Toolkit may still be open in the server base `elektron_ka` instead of `ka-demo`. Check `СтрокаСоединенияИнформационнойБазы()` first and never change data there.
  - The MCP session sees new extension metadata only after `restart_1c_session`.
- **`b24-dev-mcp`** holds the Bitrix24 REST docs. It isn't relevant to this project; it came along with the skills.

### Skills and running their scripts on macOS

`.claude/skills/` are vendored copies from `../b24-task-timesheet`. Don't hand-edit them. The 1C skills (`cfe-*`, `meta-*`, `form-*`, `db-*` and others) cover creating, editing and validating the extension XML and loading it into the base.

Use skill `/code-scout` for non-trivial repository discovery to delegate broad code reading to a lower-cost subagent scout and keep irrelevant file contents out of the primary agent's context.

The skill docs show `powershell.exe -NoProfile -File …/scripts/<name>.ps1`, and that binary doesn't exist here. Every script has a Python twin with the same `-Param` arguments (`pwsh -NoProfile -File …ps1` also works):

```bash
# validate an extension against the KA dump — run after every change
python3 .claude/skills/cfe-validate/scripts/cfe-validate.py -ExtensionPath src/МгновеннаяОтправкаПисем -ConfigPath .local/ka-config

# load one extension into the dev base and update the DB
python3 .claude/skills/db-load-xml/scripts/db-load-xml.py -ConfigDir src/МгновеннаяОтправкаПисем -Extension МгновеннаяОтправкаПисем -UpdateDB
```

- `cfe-init` defaults `CompatibilityMode` to `Version8_3_24`. Pass `Version8_3_21`, or the extension won't load into this base.
- Run every `1cv8`/`ibcmd` command (the `db-*` scripts, test runs) outside the Claude Code sandbox. Inside it, the platform exits with 134 or hangs.
- Designer-mode commands fail with a lock error while the Configurator has the base open. If `/UpdateDBCfg` hits an exclusive lock, ask the user to close their 1C clients.
- `.bsl` module files are UTF-8 with exactly one BOM (`efbbbf`). Check the first bytes before loading, because a doubled BOM breaks compilation.

### Tests

- The framework is YAxUnit, already installed in `ka-demo`. Tests live in the server common module `мопТ_МгновеннаяОтправкаПисем` with `ИсполняемыеСценарии()`.
- Tests that write to the DB run in a rolled-back transaction, and tests never send real email. Real sending is covered only by the manual scenarios П1–П19.
- `scripts/load.sh [Extension…]` fixes BOMs, runs `cfe-validate`, loads each extension with `-Extension` and updates the DB. `scripts/run-tests.sh` runs YAxUnit headless (`1cv8c ENTERPRISE … /C"RunUnitTests=…"`) and reads the jUnit report and exit-code file. Both run outside the sandbox.
- `scripts/ui-check.sh [ok|down]` checks the form and the client notifications without a person: it builds `tools/ui-check` (an external processor) into `.local/ui-check/`, starts a 1C test client (`/TESTCLIENT`) and runs the scenario as a test manager (`/TESTMANAGER /Execute`). Stage `ok` sends three letters with Mailpit running, stage `down` stops Mailpit; it prints the windows and texts the user would see, letter states, event-log errors and what reached Mailpit, and marks its letters for deletion. Popup notifications are invisible to the test client. Run it outside the sandbox after changing the form or the client module; test-client windows appear on screen, don't click them during the run.
- Tests that touch letters create them in the rolled-back transaction; send-branch tests use a nonexistent account ref so a bug can't send real mail.
- `db-cfe-admin check` on the test extension alone reports «Переменная не определена (моп_МгновеннаяОтправкаПисем)»: the isolated check doesn't see the product extension. The test run itself compiles fine.
  - YAxUnit silently skips a test module that fails to compile and still reports success. Treat `[ERR]` in its log, or zero executed tests, as a failure.

## Development method: TDD

All code is written test-first, in small red → green → refactor cycles:

1. **Red.** Write one test for the next behavior and run it. Check that it fails for the expected reason, not because of a typo or missing setup.
2. **Green.** Write the minimum code that makes it pass. Add no behavior that no test asks for.
3. **Refactor.** Clean up code and tests while everything stays green, then run `cfe-validate`.

How this applies here:

- Tests come from the spec. Every rule the PRD lists under «Расширение тестов» gets its test before its code:
  - `ДоступностьОтправки`: all combinations of status, «Когда отправить», «Не отправлять после» and the external-resources lock;
  - `ЗахватитьУчетнуюЗапись`/`ОсвободитьУчетнуюЗапись`, including the 60-minute boundary;
  - `СнятьОтказРегламентногоЗадания`;
  - `ПаузаПередПопыткой`.
- Expected texts are copied from `PRD.md` word for word, so the tests also catch text drift.
- Keep decision logic in server functions that take plain values (status, dates, flags), not form data or live mail connections. `ДоступностьОтправки` takes `ВнешниеРесурсыЗаблокированы` and `ТекущаяДата` as parameters for exactly this reason. New rules that fit this shape go there too, not into `ОтправитьПисьмоВФоне` or the form module.
- Code that needs a real mail server is verified by the manual acceptance scenarios, not by unit tests: the background send, the client notification handler and the form glue. Before handing such a change over, say which «П…» scenarios cover it.
- A bug fix starts with a test that reproduces the bug, when the bug is in testable logic.
- A change is done only when all tests pass. Never skip or weaken a test to get green; report failures with their output.
