# ABOUTME: Zsh plugin that provides an inline AI query mode via ZLE widgets.
# ABOUTME: Press a keybinding to enter AI mode, type a query, get a command back.

# -- Configuration defaults --
ZSH_AI_PROMPT_BACKEND="${ZSH_AI_PROMPT_BACKEND:-claude}"
ZSH_AI_PROMPT_KEYBINDING="${ZSH_AI_PROMPT_KEYBINDING:-^[a}"  # Alt-A
ZSH_AI_PROMPT_SYSTEM_PROMPT="${ZSH_AI_PROMPT_SYSTEM_PROMPT:-Respond with only the command(s), no explanation. No markdown, the command should be a single line and ready to run in the terminal.}"
ZSH_AI_PROMPT_SYMBOL_STYLE="${ZSH_AI_PROMPT_SYMBOL_STYLE:-fg=magenta}"
ZSH_AI_PROMPT_TEXT_STYLE="${ZSH_AI_PROMPT_TEXT_STYLE:-fg=242}"
ZSH_AI_PROMPT_USE_CLI="${ZSH_AI_PROMPT_USE_CLI:-1}"
ZSH_AI_PROMPT_TIMEOUT="${ZSH_AI_PROMPT_TIMEOUT:-60}"  # seconds, for API requests

# sysparams[pid] gives the request subshell's own pid, so cancel can kill it.
zmodload -F zsh/system p:sysparams

# Load the active backend.
_ai_prompt_plugin_dir="${0:A:h}"
if [[ -f "$_ai_prompt_plugin_dir/backends/${ZSH_AI_PROMPT_BACKEND}.zsh" ]]; then
    source "$_ai_prompt_plugin_dir/backends/${ZSH_AI_PROMPT_BACKEND}.zsh"
fi

# -- State --
typeset -g _ZSH_AI_PROMPT_ACTIVE=0
typeset -g _ZSH_AI_PROMPT_WAITING=0
typeset -g _ZSH_AI_PROMPT_FD=''
typeset -g _ZSH_AI_PROMPT_PID=''
typeset -g _ZSH_AI_PROMPT_RESULT_MARKER='__ai_prompt_result__'
typeset -g _ZSH_AI_PROMPT_SAVED_BUFFER=''
typeset -g _ZSH_AI_PROMPT_SAVED_CURSOR=0
typeset -g _ZSH_AI_PROMPT_ANIM_FD=''
typeset -g _ZSH_AI_PROMPT_SPINNER_IDX=0

typeset -ga _ZSH_AI_PROMPT_SPINNER_FRAMES=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )

# Sets PREDISPLAY indicator text. Uses PREDISPLAY (text before the buffer)
# to avoid conflicts with zsh-autosuggestions. Trailing newline pushes
# buffer to the next line.
_ai_prompt_set_indicator() {
    PREDISPLAY="$1"$'\n'
    region_highlight=("${(@)region_highlight:#P*}"
        "P2 3 ${ZSH_AI_PROMPT_SYMBOL_STYLE}"
        "P3 ${#PREDISPLAY} ${ZSH_AI_PROMPT_TEXT_STYLE}")
}

# -- Preserve PREDISPLAY highlights across syntax highlighting --
# Syntax highlighting plugins (fast-syntax-highlighting, zsh-syntax-highlighting)
# rebuild region_highlight from scratch on every keystroke, which strips our
# P-prefixed PREDISPLAY entries. We wrap the highlight function to save and
# restore P entries around its execution.
_ai_prompt_highlight() {
    if (( _ZSH_AI_PROMPT_ACTIVE || _ZSH_AI_PROMPT_WAITING )); then
        # Regenerate PREDISPLAY styling on every call. ZLE adjusts
        # region_highlight positions for BUFFER changes, which
        # corrupts P-entries (they reference PREDISPLAY, not BUFFER).
        region_highlight=(
            "P2 3 ${ZSH_AI_PROMPT_SYMBOL_STYLE}"
            "P3 ${#PREDISPLAY} ${ZSH_AI_PROMPT_TEXT_STYLE}")
        return
    fi
    local -a _ai_p_save=("${(@M)region_highlight:#P*}")
    _ai_prompt_orig_zsh_highlight
    (( ${#_ai_p_save} )) && region_highlight=("${(@)region_highlight:#P*}" "${_ai_p_save[@]}")
}

# Runs at load and again on every activation, so a highlighter that loads
# after this plugin (or is re-sourced) still gets wrapped.
_ai_prompt_wrap_highlighter() {
    (( $+functions[_zsh_highlight] )) || return 0
    [[ "${functions[_zsh_highlight]}" == "${functions[_ai_prompt_highlight]}" ]] && return 0
    functions[_ai_prompt_orig_zsh_highlight]="${functions[_zsh_highlight]}"
    functions[_zsh_highlight]="${functions[_ai_prompt_highlight]}"
}
_ai_prompt_wrap_highlighter

# -- Backend dispatch --
_ai_prompt_query() {
    local fn="_ai_prompt_query_${ZSH_AI_PROMPT_BACKEND}"
    if (( $+functions[$fn] )); then
        "$fn" "$1" "$ZSH_AI_PROMPT_SYSTEM_PROMPT"
    else
        echo "ai-prompt: unknown backend '$ZSH_AI_PROMPT_BACKEND'" >&2
        return 1
    fi
}

# -- Model resolution --
# Returns the model the active backend will use, for display in the indicator.
# Each backend defines _ai_prompt_model_<backend> and uses it for its queries.
_ai_prompt_effective_model() {
    local fn="_ai_prompt_model_${ZSH_AI_PROMPT_BACKEND}"
    if (( $+functions[$fn] )); then
        "$fn"
    else
        echo "$ZSH_AI_PROMPT_BACKEND"
    fi
}

# -- Custom keymap --
# Inherits all bindings from main so normal editing works in AI mode.
# `bindkey -N` copies main as it is at that moment, so this runs again on
# every activation to pick up bindings that plugins added after this one.
_ai_prompt_build_keymap() {
    bindkey -N ai-prompt main
    bindkey -M ai-prompt '^M'    _ai_prompt_submit   # Enter
    bindkey -M ai-prompt '^['    _ai_prompt_cancel    # Escape (standalone, after KEYTIMEOUT)
    bindkey -M ai-prompt '^[^['  _ai_prompt_cancel    # Double-Escape (instant cancel)
    bindkey -M ai-prompt '^C'    _ai_prompt_cancel    # Ctrl-C
    bindkey -M ai-prompt "$ZSH_AI_PROMPT_KEYBINDING" _ai_prompt_activate
}
_ai_prompt_build_keymap

# -- Spinner animation --
# Advances the spinner by one frame on each tick from the animation pipe.
_ai_prompt_animate() {
    local fd="$1"
    read -r -u "$fd" _ 2>/dev/null || return
    (( _ZSH_AI_PROMPT_WAITING )) || return
    _ZSH_AI_PROMPT_SPINNER_IDX=$(( (_ZSH_AI_PROMPT_SPINNER_IDX + 1) % ${#_ZSH_AI_PROMPT_SPINNER_FRAMES} ))
    _ai_prompt_set_indicator "  ${_ZSH_AI_PROMPT_SPINNER_FRAMES[$_ZSH_AI_PROMPT_SPINNER_IDX+1]} thinking..."
    zle -R
}
zle -N _ai_prompt_animate

# -- Widgets --

_ai_prompt_activate() {
    # Detect stale state from SIGINT clearing ZLE without calling our cancel widget.
    if (( _ZSH_AI_PROMPT_ACTIVE || _ZSH_AI_PROMPT_WAITING )) && [[ -z "$PREDISPLAY" ]]; then
        _ZSH_AI_PROMPT_ACTIVE=0
        _ZSH_AI_PROMPT_WAITING=0
    fi

    # Ignore if already active or waiting for a response.
    (( _ZSH_AI_PROMPT_ACTIVE || _ZSH_AI_PROMPT_WAITING )) && return

    # Save current state.
    _ZSH_AI_PROMPT_SAVED_BUFFER="$BUFFER"
    _ZSH_AI_PROMPT_SAVED_CURSOR=$CURSOR
    _ZSH_AI_PROMPT_ACTIVE=1
    _ZSH_AI_PROMPT_WAITING=0

    # Clear buffer for query input.
    BUFFER=''
    CURSOR=0
    _ai_prompt_set_indicator "  ⟡ AI mode ($(_ai_prompt_effective_model)) — Enter to send, Esc to cancel"

    # Switch to AI keymap.
    _ai_prompt_build_keymap
    _ai_prompt_wrap_highlighter
    zle -K ai-prompt
    zle reset-prompt
}
zle -N _ai_prompt_activate

_ai_prompt_submit() {
    # If AI mode is not active, fall through to normal accept-line.
    if (( ! _ZSH_AI_PROMPT_ACTIVE || _ZSH_AI_PROMPT_WAITING )); then
        zle accept-line
        return
    fi

    local query="$BUFFER"

    # Nothing to submit.
    if [[ -z "$query" ]]; then
        _ai_prompt_cancel
        return
    fi

    # Enter waiting state.
    _ZSH_AI_PROMPT_WAITING=1
    _ZSH_AI_PROMPT_SPINNER_IDX=0
    BUFFER=''
    CURSOR=0
    _ai_prompt_set_indicator "  ${_ZSH_AI_PROMPT_SPINNER_FRAMES[1]} thinking..."

    zle reset-prompt

    # Start animation ticker — background process writes a line every 80ms.
    # Closing the read end sends SIGPIPE to kill the background process.
    exec {_ZSH_AI_PROMPT_ANIM_FD}< <(
        while true; do sleep 0.08; echo; done
    )
    zle -F -w "$_ZSH_AI_PROMPT_ANIM_FD" _ai_prompt_animate

    # Launch async API call. The subshell writes its own pid first (so
    # cancel can kill it), then any backend stderr as diagnostics, then the
    # result marker with the exit status, then the response.
    exec {_ZSH_AI_PROMPT_FD}< <(
        exec 2>&1
        print -r -- "$sysparams[pid]"
        local response rc=0
        response=$(_ai_prompt_query "$query") || rc=$?
        print -r -- $'\n'"$_ZSH_AI_PROMPT_RESULT_MARKER $rc"
        print -rn -- "$response"
    )
    read -r -u "$_ZSH_AI_PROMPT_FD" _ZSH_AI_PROMPT_PID
    zle -F -w "$_ZSH_AI_PROMPT_FD" _ai_prompt_handler
}
zle -N _ai_prompt_submit

_ai_prompt_cancel() {
    # If AI mode is not active, ignore.
    (( _ZSH_AI_PROMPT_ACTIVE || _ZSH_AI_PROMPT_WAITING )) || return

    # Restore original buffer.
    BUFFER="$_ZSH_AI_PROMPT_SAVED_BUFFER"
    CURSOR=$_ZSH_AI_PROMPT_SAVED_CURSOR

    _ai_prompt_stop_request
    _ai_prompt_cleanup
}
zle -N _ai_prompt_cancel

_ai_prompt_handler() {
    local fd="$1"

    # Deregister watcher first (avoids busy-loop bug).
    zle -F "$fd"

    # Read full response. Widget handlers with -w only get the fd argument
    # (no error string), so just attempt the read.
    local output=''
    output="$(cat <&$fd 2>/dev/null)"

    # Close fd. The request subshell has exited.
    exec {fd}<&-
    _ZSH_AI_PROMPT_FD=''
    _ZSH_AI_PROMPT_PID=''

    # Split into diagnostics, exit status and response. Without the marker
    # the subshell died early, and everything it wrote is diagnostics.
    local marker=$'\n'"$_ZSH_AI_PROMPT_RESULT_MARKER "
    local diagnostics="$output" rc=1 result=''
    if [[ "$output" == *"$marker"* ]]; then
        diagnostics="${output%"$marker"*}"
        local after_marker="${output##*"$marker"}"
        rc="${after_marker%%$'\n'*}"
        [[ "$after_marker" == *$'\n'* ]] && result="${after_marker#*$'\n'}"
    fi
    result="$(_ai_prompt_clean_response "$result")"

    if (( rc == 0 )) && [[ -n "$result" ]]; then
        BUFFER="$result"
        CURSOR=${#BUFFER}
        _ai_prompt_cleanup
        zle -R
        return
    fi

    # On error or empty response, restore original buffer and say why.
    BUFFER="$_ZSH_AI_PROMPT_SAVED_BUFFER"
    CURSOR=$_ZSH_AI_PROMPT_SAVED_CURSOR
    _ai_prompt_cleanup

    local message="$(_ai_prompt_clean_response "$diagnostics")"
    [[ -n "$message" ]] || message="no command returned (exit status $rc)"
    [[ "$message" == ai-prompt:* ]] || message="ai-prompt: $message"
    zle -R
    zle -M "$message"
}
zle -N _ai_prompt_handler

# -- Response cleanup --
# Removes a markdown code fence around the whole text, then leading and
# trailing whitespace. Models sometimes fence the command despite the
# system prompt, and the fence lines would otherwise run as commands.
_ai_prompt_clean_response() {
    setopt localoptions extendedglob
    local text="$1"
    local -a lines=("${(@f)text}")
    if (( ${#lines} >= 2 )) && [[ "${lines[1]}" == '```'* && "${lines[-1]}" == '```'[[:space:]]# ]]; then
        text="${(F)lines[2,-2]}"
    fi
    text="${text##[[:space:]]##}"
    text="${text%%[[:space:]]##}"
    print -rn -- "$text"
}

# -- Request teardown --
# Closes the response fd and kills the request subshell with everything it
# started (curl, jq, CLI). Closing the fd alone leaves them running until
# they next write.
_ai_prompt_stop_request() {
    if [[ -n "$_ZSH_AI_PROMPT_FD" ]]; then
        zle -F "$_ZSH_AI_PROMPT_FD" 2>/dev/null
        exec {_ZSH_AI_PROMPT_FD}<&- 2>/dev/null
        _ZSH_AI_PROMPT_FD=''
    fi
    if [[ -n "$_ZSH_AI_PROMPT_PID" ]]; then
        _ai_prompt_kill_tree "$_ZSH_AI_PROMPT_PID"
        _ZSH_AI_PROMPT_PID=''
    fi
}

# Kills a process and its descendants, children first so none get
# reparented out of reach.
_ai_prompt_kill_tree() {
    local child
    for child in $(pgrep -P "$1"); do
        _ai_prompt_kill_tree "$child"
    done
    kill "$1" 2>/dev/null
}

# -- Cleanup helper --
_ai_prompt_cleanup() {
    _ZSH_AI_PROMPT_ACTIVE=0
    _ZSH_AI_PROMPT_WAITING=0
    PREDISPLAY=''
    region_highlight=("${(@)region_highlight:#P*}")

    # Stop animation ticker.
    if [[ -n "$_ZSH_AI_PROMPT_ANIM_FD" ]]; then
        zle -F "$_ZSH_AI_PROMPT_ANIM_FD" 2>/dev/null
        exec {_ZSH_AI_PROMPT_ANIM_FD}<&- 2>/dev/null
        _ZSH_AI_PROMPT_ANIM_FD=''
    fi

    zle reset-prompt
    zle -K main
}

# -- Stale state after Ctrl-C --
# Ctrl-C usually arrives as SIGINT, which aborts the line without running
# _ai_prompt_cancel. AI state still set when a new line starts is therefore
# stale: stop any pending request and reset.
_ai_prompt_line_init() {
    (( _ZSH_AI_PROMPT_ACTIVE || _ZSH_AI_PROMPT_WAITING )) || return 0
    _ai_prompt_stop_request
    _ai_prompt_cleanup
}
autoload -Uz add-zle-hook-widget
add-zle-hook-widget zle-line-init _ai_prompt_line_init

# -- Bind the activation key --
bindkey "$ZSH_AI_PROMPT_KEYBINDING" _ai_prompt_activate
