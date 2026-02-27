# ABOUTME: Zsh plugin that provides an inline AI query mode via ZLE widgets.
# ABOUTME: Press a keybinding to enter AI mode, type a query, get a command back.

# -- Configuration defaults --
ZSH_AI_PROMPT_BACKEND="${ZSH_AI_PROMPT_BACKEND:-claude}"
ZSH_AI_PROMPT_KEYBINDING="${ZSH_AI_PROMPT_KEYBINDING:-^[a}"  # Alt-A
ZSH_AI_PROMPT_SYSTEM_PROMPT="${ZSH_AI_PROMPT_SYSTEM_PROMPT:-Respond with only the command(s), no explanation.}"
ZSH_AI_PROMPT_SYMBOL_STYLE="${ZSH_AI_PROMPT_SYMBOL_STYLE:-fg=magenta}"
ZSH_AI_PROMPT_TEXT_STYLE="${ZSH_AI_PROMPT_TEXT_STYLE:-fg=242}"

# Load the active backend.
_ai_prompt_plugin_dir="${0:A:h}"
if [[ -f "$_ai_prompt_plugin_dir/backends/${ZSH_AI_PROMPT_BACKEND}.zsh" ]]; then
    source "$_ai_prompt_plugin_dir/backends/${ZSH_AI_PROMPT_BACKEND}.zsh"
fi

# -- State --
typeset -g _ZSH_AI_PROMPT_ACTIVE=0
typeset -g _ZSH_AI_PROMPT_WAITING=0
typeset -g _ZSH_AI_PROMPT_FD=''
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
}

# -- Backend dispatch --
_ai_prompt_query() {
    local fn="_ai_prompt_query_${ZSH_AI_PROMPT_BACKEND}"
    if (( $+functions[$fn] )); then
        "$fn" "$1" "$ZSH_AI_PROMPT_SYSTEM_PROMPT"
    else
        echo "ai-prompt: unknown backend '$ZSH_AI_PROMPT_BACKEND'" >&2
    fi
}

# -- Model resolution --
# Returns the effective model name for display in the indicator.
_ai_prompt_effective_model() {
    if [[ -n "$ZSH_AI_PROMPT_MODEL" ]]; then
        echo "$ZSH_AI_PROMPT_MODEL"
        return
    fi
    case "$ZSH_AI_PROMPT_BACKEND" in
        claude)
            if (( $+commands[claude] )); then echo "haiku"
            else echo "claude-haiku-4-5"; fi ;;
        openai)  echo "gpt-4.1-nano" ;;
        gemini)  echo "${GEMINI_MODEL:-gemini-2.5-flash-lite}" ;;
        ollama)  echo "llama3" ;;
        *)       echo "$ZSH_AI_PROMPT_BACKEND" ;;
    esac
}

# -- Custom keymap --
# Inherits all bindings from main so normal editing works in AI mode.
bindkey -N ai-prompt main
bindkey -M ai-prompt '^M'    _ai_prompt_submit   # Enter
bindkey -M ai-prompt '^['    _ai_prompt_cancel    # Escape (standalone, after KEYTIMEOUT)
bindkey -M ai-prompt '^[^['  _ai_prompt_cancel    # Double-Escape (instant cancel)
bindkey -M ai-prompt '^C'    _ai_prompt_cancel    # Ctrl-C

# -- Spinner animation --
# Advances the spinner by one frame on each tick from the animation pipe.
_ai_prompt_animate() {
    local fd="$1"
    read -r -u "$fd" _ 2>/dev/null || return
    (( _ZSH_AI_PROMPT_WAITING )) || return
    _ZSH_AI_PROMPT_SPINNER_IDX=$(( (_ZSH_AI_PROMPT_SPINNER_IDX + 1) % ${#_ZSH_AI_PROMPT_SPINNER_FRAMES} ))
    _ai_prompt_set_indicator "  ${_ZSH_AI_PROMPT_SPINNER_FRAMES[$_ZSH_AI_PROMPT_SPINNER_IDX+1]} thinking..."
    region_highlight=("${(@)region_highlight:#P*}"
        "P2 3 ${ZSH_AI_PROMPT_SYMBOL_STYLE}"
        "P3 ${#PREDISPLAY} ${ZSH_AI_PROMPT_TEXT_STYLE}")
    zle -R
}
zle -N _ai_prompt_animate

# -- Widgets --

_ai_prompt_activate() {
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
    region_highlight=("${(@)region_highlight:#P*}"
        "P2 3 ${ZSH_AI_PROMPT_SYMBOL_STYLE}"
        "P3 ${#PREDISPLAY} ${ZSH_AI_PROMPT_TEXT_STYLE}")

    # Switch to AI keymap.
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
    region_highlight=("${(@)region_highlight:#P*}"
        "P2 3 ${ZSH_AI_PROMPT_SYMBOL_STYLE}"
        "P3 ${#PREDISPLAY} ${ZSH_AI_PROMPT_TEXT_STYLE}")

    zle reset-prompt

    # Start animation ticker — background process writes a line every 80ms.
    # Closing the read end sends SIGPIPE to kill the background process.
    exec {_ZSH_AI_PROMPT_ANIM_FD}< <(
        while true; do sleep 0.08; echo; done
    )
    zle -F -w "$_ZSH_AI_PROMPT_ANIM_FD" _ai_prompt_animate

    # Launch async API call.
    exec {_ZSH_AI_PROMPT_FD}< <(
        _ai_prompt_query "$query" 2>/dev/null
    )
    zle -F -w "$_ZSH_AI_PROMPT_FD" _ai_prompt_handler
}
zle -N _ai_prompt_submit

_ai_prompt_cancel() {
    # If AI mode is not active, ignore.
    (( _ZSH_AI_PROMPT_ACTIVE || _ZSH_AI_PROMPT_WAITING )) || return

    # Restore original buffer.
    BUFFER="$_ZSH_AI_PROMPT_SAVED_BUFFER"
    CURSOR=$_ZSH_AI_PROMPT_SAVED_CURSOR

    # Kill pending async call if any.
    if [[ -n "$_ZSH_AI_PROMPT_FD" ]]; then
        zle -F "$_ZSH_AI_PROMPT_FD" 2>/dev/null
        exec {_ZSH_AI_PROMPT_FD}<&- 2>/dev/null
        _ZSH_AI_PROMPT_FD=''
    fi

    _ai_prompt_cleanup
}
zle -N _ai_prompt_cancel

_ai_prompt_handler() {
    local fd="$1"

    # Deregister watcher first (avoids busy-loop bug).
    zle -F "$fd"

    # Read full response. Widget handlers with -w only get the fd argument
    # (no error string), so just attempt the read.
    local result=''
    result="$(cat <&$fd 2>/dev/null)"

    # Close fd.
    exec {fd}<&-
    _ZSH_AI_PROMPT_FD=''

    if [[ -n "$result" ]]; then
        BUFFER="$result"
        CURSOR=${#BUFFER}
    else
        # On error or empty response, restore original buffer.
        BUFFER="$_ZSH_AI_PROMPT_SAVED_BUFFER"
        CURSOR=$_ZSH_AI_PROMPT_SAVED_CURSOR
    fi

    _ai_prompt_cleanup
    zle -R
}
zle -N _ai_prompt_handler

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

    # Switch back to main keymap AFTER reset-prompt to ensure the
    # keymap change persists in async zle -F handler contexts.
    zle reset-prompt
    zle -K main
}

# -- Bind the activation key --
bindkey "$ZSH_AI_PROMPT_KEYBINDING" _ai_prompt_activate
