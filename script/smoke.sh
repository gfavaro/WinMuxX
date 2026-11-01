#!/bin/bash
# Smoke test for a running WinMuxX in either mode (virtual workspaces or native Spaces),
# read from doctor. It uses only its own TextEdit window (and skips window checks when
# TextEdit is already open, so no user document is touched), returns every window it
# moves and the focus it changes, and reports PASS/FAIL/SKIP per check.
#
#   script/smoke.sh            against the installed app (`winmuxx`)
#   script/smoke.sh --dev      against WinMuxX Native Dev
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
# The app macOS has in front, not WinMuxX's own focus record.
front_app() { lsappinfo info -only name "$(lsappinfo front)" | head -1 | sed 's/.*"\(.*\)".*/\1/'; }

helper_dir=$(mktemp -d)
trap 'rm -rf "$helper_dir"' EXIT
win() { "$helper_dir/smoke-window" "$@"; }
# Whether frame $2 rests on frame $1, with WinMuxX's own tolerance.
rests_on() { awk -v a="$1" -v b="$2" 'BEGIN { split(a, t); split(b, f)
    d1 = f[1] - t[1]; d2 = f[2] - t[2]; if (d1 < 0) d1 = -d1; if (d2 < 0) d2 = -d2
    exit !(d1 <= 4 && d2 <= 4 && f[3] >= t[3] - 24 && f[4] >= t[4] - 24) }'; }

crashes_before=$(crash_count)
doctor=$(wm doctor)
[ -n "$doctor" ] || { fail "WinMuxX is running and answers doctor"; exit 1; }
if grep -q "Native Spaces" <<<"$doctor"; then
    mode=native
    grep -q "^Tiling: Native tiling active" <<<"$doctor" && pass "native tiling active" || fail "native tiling active: $(grep '^Tiling' <<<"$doctor")"
    grep -q "Space switching:.*Accessibility: granted" <<<"$doctor" && pass "Space switching available" || fail "Space switching available"
    grep -q "Window moves:.*(available)" <<<"$doctor" && pass "window moves available" || fail "window moves available"
else
    mode=virtual
    grep -q "enabled: true" <<<"$doctor" && pass "virtual workspaces, tiling enabled" || fail "virtual workspaces, tiling enabled"
fi
echo "Mode: $mode"
start_focus=$(wm list-workspaces --focused)

desktops=$(wm list-workspaces --all | tr '\n' ' ')
[ -n "${desktops// }" ] && pass "list-workspaces: $desktops" || fail "list-workspaces"
monitors=$(wm list-monitors | wc -l | tr -d ' ')
pass "list-monitors: $monitors display(s)"

if pgrep -x TextEdit >/dev/null; then
    skip "window checks (TextEdit is open; the smoke test only moves its own windows)"
elif ! swiftc -O -o "$helper_dir/smoke-window" script/smoke-window.swift 2>/dev/null; then
    fail "compile the window helper (script/smoke-window.swift)"
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
        fail "test window adopted"
    else
        pass "test window $window adopted"
        home=$(space_of "$window")
        sleep 1
        tile=$(win frame "$window")
        # An app moving its own tiled window: put back once it is still.
        win nudge "$window"
        sleep 1
        rests_on "$tile" "$(win frame "$window")" && pass "a window its app moved is put back on its tile" ||
            fail "a window its app moved is put back: tile $tile, now $(win frame "$window")"
        # An app that moves it again each time it is put back is left alone after three tries.
        fight=$(win fight "$window" 4)
        putbacks=$(sed 's/putbacks=\([0-9]*\).*/\1/' <<<"$fight")
        [ "$putbacks" -ge 1 ] && [ "$putbacks" -le 3 ] && grep -q "resting=false" <<<"$fight" &&
            pass "an app that keeps moving its window is left alone ($putbacks more put-backs; three per tile in 10 s)" ||
            fail "an app that keeps moving its window: $fight (expected 1 to 3 put-backs, then left alone)"
        output=$(wm retile)
        sleep 1
        rests_on "$tile" "$(win frame "$window")" && pass "retile puts it back ($output)" || fail "retile: $output; now $(win frame "$window")"
        # Another desktop on any display that has more than one; the window can join any desktop.
        other=$(wm list-workspaces --all --format '%{workspace} %{workspace-is-visible}' | awk -v home="$home" '$2 == "false" && $1 != home { print $1; exit }')
        if [ -n "$other" ]; then
            wm move-node-to-workspace --window-id "$window" "$other" >/dev/null
            sleep 0.5
            [ "$(space_of "$window")" = "$other" ] && pass "move-node-to-workspace $other" || fail "move-node-to-workspace $other"
            # Virtual workspaces hide a window that is not showing by parking it off screen.
            [ "$mode" = virtual ] && { [ "$(win shown "$window")" = hidden ] && pass "a window on a hidden workspace is out of sight" ||
                fail "a window on a hidden workspace is out of sight: $(win frame "$window")"; }
            wm move-node-to-workspace --window-id "$window" "$home" >/dev/null
            sleep 0.5
            [ "$(space_of "$window")" = "$home" ] && pass "move back to workspace $home" || fail "move back to workspace $home"
            [ "$mode" = virtual ] && { [ "$(win shown "$window")" = shown ] && pass "and it is shown again" ||
                fail "shown again after moving back: $(win frame "$window")"; }
        else
            skip "move-node-to-workspace (no other desktop)"
        fi
        if [ -n "$other" ]; then
            start=$(wm list-workspaces --monitor focused --visible)
            wm move-node-to-workspace --window-id "$window" --focus-follows-window "$other" >/dev/null
            sleep 1.5
            [ "$(front_app)" = "TextEdit" ] && pass "focus follows a moved window (macOS front app)" || fail "focus follows a moved window: front is $(front_app)"
            wm workspace "$home" >/dev/null
            sleep 1.5
            wm focus --window-id "$window" >/dev/null
            sleep 1.5
            [ "$(front_app)" = "TextEdit" ] && [ "$(space_of "$window")" = "$other" ] && pass "focus --window-id on a workspace not showing" ||
                fail "focus --window-id on a workspace not showing: front is $(front_app)"
            wm move-node-to-workspace --window-id "$window" "$home" >/dev/null
            sleep 0.5
            wm workspace "$start" >/dev/null 2>&1
        fi
        if [ "$monitors" -ge 2 ]; then
            before=$(space_of "$window")
            output=$(wm move-node-to-monitor --window-id "$window" --wrap-around next)
            sleep 0.5
            away=$(space_of "$window")
            [ -n "$away" ] && [ "$away" != "$before" ] && pass "move-node-to-monitor next (desktop $away)" ||
                fail "move-node-to-monitor next: from $before, now ${away:-unknown}: ${output:-no output}"
            wm move-node-to-workspace --window-id "$window" "$home" >/dev/null
            sleep 0.5
            [ "$(space_of "$window")" = "$home" ] && pass "move back from the other display" || fail "move back from the other display"
        else
            skip "move-node-to-monitor (one display)"
        fi
    fi
    # The scratch document is unchanged, so nothing is written.
    osascript -e 'tell application "TextEdit" to quit saving yes' >/dev/null 2>&1
    rm -rf "$scratch"
    sleep 2
    wm doctor >/dev/null && pass "WinMuxX survives the test app quitting" || fail "WinMuxX survives the test app quitting"
fi

# The sidebar's main use: changing the workspace of a display the pointer is not on.
# Native mode moves the pointer there for the swipe; it must come back. (The sidebar's
# own path, which also keeps focus, has no CLI entry; unit tests cover it.)
mouse=$(wm list-monitors --mouse --format '%{monitor-id}')
layout=$(wm list-workspaces --all --format '%{workspace} %{monitor-id} %{workspace-is-visible}')
away_shown=$(awk -v m="$mouse" '$2 != m && $3 == "true" { print $1 " " $2; exit }' <<<"$layout")
away_display=${away_shown#* }
away_shown=${away_shown% *}
away_target=$(awk -v m="$mouse" -v d="$away_display" '$2 != m && $2 == d && $3 == "false" { print $1; exit }' <<<"$layout")
shown() { wm list-workspaces --all --format '%{workspace} %{workspace-is-visible}' | awk -v w="$1" '$1 == w { print $2 }'; }
if [ -z "$away_target" ]; then
    skip "switch the other display's workspace (no display without the pointer has two workspaces)"
else
    started=$(perl -MTime::HiRes=time -e 'printf "%d", time * 1000')
    wm workspace "$away_target" >/dev/null
    for _ in $(seq 1 30); do [ "$(shown "$away_target")" = true ] && break; sleep 0.1; done
    landed=$(( $(perl -MTime::HiRes=time -e 'printf "%d", time * 1000') - started ))
    [ "$(shown "$away_target")" = true ] && pass "switch the other display to workspace $away_target (${landed} ms)" ||
        fail "switch the other display to workspace $away_target"
    # The pointer comes back from the swipe, unless focus followed the switch and the
    # config's on-focused-monitor-changed moves it to the focused display.
    now_mouse=$(wm list-monitors --mouse --format '%{monitor-id}')
    now_focused=$(wm list-monitors --focused --format '%{monitor-id}')
    [ "$now_mouse" = "$mouse" ] && pass "pointer returned to its display" ||
        { [ "$now_mouse" = "$now_focused" ] && pass "pointer followed focus to display $now_focused (config callback)" ||
            fail "pointer left on display $now_mouse; focus is on display $now_focused"; }
    # Two requests back to back, as rapid sidebar clicks send them: the last one wins.
    wm workspace "$away_shown" >/dev/null & wm workspace "$away_target" >/dev/null; wait
    wm workspace "$away_shown" >/dev/null
    sleep 0.3
    [ "$(shown "$away_shown")" = true ] && pass "rapid switches on the other display end on workspace $away_shown" ||
        fail "rapid switches on the other display: workspace $away_shown not showing"
fi

restore_output=$([ -n "$start_focus" ] && wm workspace "$start_focus")
# Native focus lands after the command returns.
for _ in $(seq 1 30); do [ "$(wm list-workspaces --focused)" = "$start_focus" ] && break; sleep 0.1; done
[ "$(wm list-workspaces --focused)" = "$start_focus" ] && pass "focus returned to workspace $start_focus" ||
    fail "focus returned to workspace $start_focus: now $(wm list-workspaces --focused) (${restore_output:-no output})"

probe=$([ "$mode" = native ] && wm doctor --simulate-native-pan)
if [ "$mode" = virtual ]; then
    skip "native scrolling pan (virtual mode)"
elif grep -q "No visible scrolling desktop" <<<"$probe"; then
    skip "scrolling pan (no scrolling desktop showing)"
else
    lag=$(grep -o 'p90 [0-9]* ms' <<<"$probe" | head -1 | awk '{ print $2 }')
    if grep -q "over 0 samples" <<<"$probe"; then
        skip "scrolling pan (every column fits on screen; nothing to pan)"
    else
        [ -n "$lag" ] && [ "$lag" -le 100 ] && pass "scrolling pan p90 lag ${lag} ms" || fail "scrolling pan lag: $(grep 'lag' <<<"$probe" | head -1)"
    fi
fi

[ "$(crash_count)" -eq "$crashes_before" ] && pass "no new crash reports" || fail "new crash report in ~/Library/Logs/DiagnosticReports"
echo
[ "$failures" -eq 0 ] && echo "Smoke ($mode): all checks passed" || echo "Smoke ($mode): $failures check(s) failed"
exit "$failures"
