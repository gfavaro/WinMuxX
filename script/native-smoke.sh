#!/bin/bash
# Native Spaces smoke test for a running WinMuxX in native mode. It uses only its own
# TextEdit windows (and skips window moves when TextEdit is already open, so no user
# document is touched), returns every window it moves, and reports PASS/FAIL per check.
#
#   script/native-smoke.sh            against the installed app (`winmuxx`)
#   script/native-smoke.sh --dev      against WinMuxX Native Dev
set -uo pipefail
cd "$(dirname "$0")/.."

cli=(winmuxx)
[ "${1:-}" = "--dev" ] && cli=(./script/native-dev.sh cli)
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }
skip() { echo "SKIP  $1"; }
wm() { "${cli[@]}" "$@" 2>&1; }
space_of() { wm list-windows --monitor all --format '%{window-id} %{workspace}' | awk -v id="$1" '$1 == id { print $2 }'; }
crash_count() { ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^WinMux'; }

crashes_before=$(crash_count)
doctor=$(wm doctor)
grep -q "Native Spaces" <<<"$doctor" || { fail "WinMuxX is running in native mode"; exit 1; }
grep -q "^Tiling: Native tiling active" <<<"$doctor" && pass "native tiling active" || fail "native tiling active: $(grep '^Tiling' <<<"$doctor")"
grep -q "Space switching:.*Accessibility: granted" <<<"$doctor" && pass "Space switching available" || fail "Space switching available"
grep -q "Window moves:.*(available)" <<<"$doctor" && pass "window moves available" || fail "window moves available"

desktops=$(wm list-workspaces --all | tr '\n' ' ')
[ -n "${desktops// }" ] && pass "list-workspaces: $desktops" || fail "list-workspaces"
monitors=$(wm list-monitors | wc -l | tr -d ' ')
pass "list-monitors: $monitors display(s)"

if pgrep -x TextEdit >/dev/null; then
    skip "window moves (TextEdit is open; the smoke test only moves its own windows)"
else
    scratch=$(mktemp -d)
    echo smoke > "$scratch/winmuxx-smoke-a.txt"
    open -a TextEdit "$scratch/winmuxx-smoke-a.txt"
    window=""
    for _ in $(seq 1 30); do
        sleep 0.5
        window=$(wm list-windows --monitor all --format '%{window-id} %{app-name} %{window-title}' |
            awk '/TextEdit/ && /winmuxx-smoke-a/ { print $1; exit }')
        [ -n "$window" ] && break
    done
    if [ -z "$window" ]; then
        fail "test window adopted by native tiling"
    else
        pass "test window $window adopted"
        home=$(space_of "$window")
        # Another desktop on any display that has more than one; the window can join any desktop.
        other=$(wm list-workspaces --all --format '%{workspace} %{workspace-is-visible}' | awk -v home="$home" '$2 == "false" && $1 != home { print $1; exit }')
        if [ -n "$other" ]; then
            wm move-node-to-workspace --window-id "$window" "$other" >/dev/null
            sleep 0.5
            [ "$(space_of "$window")" = "$other" ] && pass "move-node-to-workspace $other" || fail "move-node-to-workspace $other"
            wm move-node-to-workspace --window-id "$window" "$home" >/dev/null
            sleep 0.5
            [ "$(space_of "$window")" = "$home" ] && pass "move back to desktop $home" || fail "move back to desktop $home"
        else
            skip "move-node-to-workspace (no other desktop)"
        fi
        if [ "$monitors" -ge 2 ]; then
            before=$(space_of "$window")
            wm move-node-to-monitor --window-id "$window" next >/dev/null
            sleep 0.5
            away=$(space_of "$window")
            [ -n "$away" ] && [ "$away" != "$before" ] && pass "move-node-to-monitor next (desktop $away)" || fail "move-node-to-monitor next"
            wm move-node-to-workspace --window-id "$window" "$home" >/dev/null
            sleep 0.5
            [ "$(space_of "$window")" = "$home" ] && pass "move back from the other display" || fail "move back from the other display"
        else
            skip "move-node-to-monitor (one display)"
        fi
    fi
    osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
    rm -rf "$scratch"
    sleep 2
    wm doctor >/dev/null && pass "WinMuxX survives the test app quitting" || fail "WinMuxX survives the test app quitting"
fi

probe=$(wm doctor --simulate-native-pan)
if grep -q "No visible scrolling desktop" <<<"$probe"; then
    skip "scrolling pan (no scrolling desktop showing)"
else
    lag=$(grep -o 'p90 [0-9]* ms' <<<"$probe" | head -1 | grep -o '[0-9]*')
    [ -n "$lag" ] && [ "$lag" -le 100 ] && pass "scrolling pan p90 lag ${lag} ms" || fail "scrolling pan lag: $(grep 'lag' <<<"$probe" | head -1)"
fi

[ "$(crash_count)" -eq "$crashes_before" ] && pass "no new crash reports" || fail "new crash report in ~/Library/Logs/DiagnosticReports"
echo
[ "$failures" -eq 0 ] && echo "Native smoke: all checks passed" || echo "Native smoke: $failures check(s) failed"
exit "$failures"
