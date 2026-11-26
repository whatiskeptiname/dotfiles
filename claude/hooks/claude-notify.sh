#!/usr/bin/env bash
# Desktop notifications for Claude Code, with context. Called by the Stop and
# Notification hooks in ~/.claude/settings.json; reads the hook's JSON on stdin.
#
#   Stop          "Claude · <project> · done in 2m 13s"
#                 ↳ your request · first line of Claude's reply
#   Notification  "Claude · <project> · needs you"
#                 what it's waiting for, and the pending command or file
#
# Clicking the notification focuses the window Claude runs in. Each session
# keeps one notification, replaced by the next. Permission prompts and
# questions use critical urgency so swaync shows them during DND.

input=$(cat)
# Do the work in the background so the hook returns at once.
(
get() { jq -r "$1 // empty" <<< "$input"; }
event=$(get .hook_event_name)
cwd=$(get .cwd)
transcript=$(get .transcript_path)
session=$(get .session_id)

project=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
project=$(basename "${project:-${cwd:-?}}")

# One line, at most N chars, safe for notification markup. With "md", also
# drop markdown symbols (for Claude's reply; commands keep theirs).
clean() {
    local strip='s/^//'
    [ "$2" = md ] && strip='s/[*`#>]//g'
    tr '\n' ' ' | sed -e "$strip" -e 's/  */ /g' -e 's/^ //' -e 's/ $//' |
        awk -v n="$1" '{ if (length($0) > n) print substr($0, 1, n - 1) "…"; else print }' |
        sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Your latest request and when you sent it: the last user entry typed by a
# human (skill text, reminders and tool results are user entries too).
prompt= start=
if [ -r "$transcript" ]; then
    IFS=$'\t' read -r start prompt < <(tail -n 2000 "$transcript" | jq -rs '
        [ .[] | select(.type == "user" and .origin.kind? == "human")
          | [ .timestamp,
              (.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end
               | gsub("[\t\n]"; " ")) ] ]
        | last // empty | @tsv')
fi

case "$event" in
Stop)
    # The opening line of Claude's last reply: it leads with the outcome.
    reply=$(tail -n 400 "$transcript" 2>/dev/null | jq -rs '
        [ .[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text ]
        | last // ""' | awk 'NF { print; exit }')

    # Time since your request.
    took=
    if [ -n "$start" ]; then
        s=$(( $(date +%s) - $(date -d "$start" +%s) ))
        if (( s >= 60 )); then took=" in $((s / 60))m $((s % 60))s"; elif (( s >= 5 )); then took=" in ${s}s"; fi
    fi

    title="Claude · $project · done$took"
    body=""
    [ -n "$prompt" ] && body="↳ $(clean 90 <<< "$prompt")"
    [ -n "$reply" ] && body="${body:+$body
}$(clean 180 md <<< "$reply")"
    urgency=normal icon=dialog-information sound=complete.oga
    ;;
Notification)
    message=$(get .message)
    type=$(get .notification_type)
    # What it's waiting on: the latest tool call, e.g. the command to approve.
    pending=$(tail -n 200 "$transcript" 2>/dev/null | jq -rs '
        [ .[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") ] | last
        | if . == null then "" else
            .name + ": " + ((.input.command // .input.file_path // .input.url // .input.description
                             // (.input.questions[0].question?) // "") | tostring)
          end')
    title="Claude · $project · needs you"
    body=$(clean 120 <<< "${message:-Waiting for you}")
    if [ "$type" = permission_prompt ] && [ -n "$pending" ]; then
        body="$body
$(clean 160 <<< "$pending")"
    elif [ -n "$prompt" ]; then
        body="$body
↳ $(clean 90 <<< "$prompt")"
    fi
    case "$type" in
        permission_prompt|elicitation_dialog) urgency=critical ;;
        *) urgency=normal ;;
    esac
    icon=dialog-question sound=message-new-instant.oga
    ;;
*) exit 0 ;;
esac

pw-play "/usr/share/sounds/freedesktop/stereo/$sound" &>/dev/null &

# The window Claude runs in: the nearest ancestor process that owns one.
window_pid=
pids=" $(swaymsg -t get_tree 2>/dev/null | jq -r '.. | .pid? // empty' | tr '\n' ' ') "
p=$PPID
while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    case "$pids" in *" $p "*) window_pid=$p; break ;; esac
    p=$(awk '{ print $4 }' "/proc/$p/stat" 2>/dev/null)
done

action=$(notify-send -a "Claude Code" -i "$icon" -u "$urgency" \
    -h "string:x-canonical-private-synchronous:claude-$session" \
    ${window_pid:+-A "default=Show"} -w "$title" "$body")
[ "$action" = default ] && [ -n "$window_pid" ] && swaymsg "[pid=$window_pid] focus" >/dev/null
) </dev/null >/dev/null 2>&1 &
exit 0
