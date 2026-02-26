# ABOUTME: Zsh plugin that provides an inline AI query mode via ZLE widgets.
# ABOUTME: Press a keybinding to enter AI mode, type a query, get a command back.

# -- Configuration defaults --
AI_PROMPT_BACKEND="${AI_PROMPT_BACKEND:-claude}"
AI_PROMPT_KEYBINDING="${AI_PROMPT_KEYBINDING:-^[a}"  # Alt-A
AI_PROMPT_SYSTEM_PROMPT="${AI_PROMPT_SYSTEM_PROMPT:-Respond with only the command(s), no explanation.}"

# Load user config if present.
[[ -f ~/.config/ai-prompt/config.zsh ]] && source ~/.config/ai-prompt/config.zsh

# Load the active backend.
_ai_prompt_plugin_dir="${0:A:h}"
if [[ -f "$_ai_prompt_plugin_dir/backends/${AI_PROMPT_BACKEND}.zsh" ]]; then
    source "$_ai_prompt_plugin_dir/backends/${AI_PROMPT_BACKEND}.zsh"
fi

# -- State --
typeset -g _AI_PROMPT_ACTIVE=0
typeset -g _AI_PROMPT_WAITING=0
typeset -g _AI_PROMPT_FD=''
typeset -g _AI_PROMPT_SAVED_BUFFER=''
typeset -g _AI_PROMPT_SAVED_CURSOR=0
typeset -g _AI_PROMPT_SAVED_TMOUT="${TMOUT:-0}"
typeset -g _AI_PROMPT_SPINNER_IDX=0

typeset -ga _AI_PROMPT_SPINNER_FRAMES=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )

# -- Backend dispatch --
_ai_prompt_query() {
    local fn="_ai_prompt_query_${AI_PROMPT_BACKEND}"
    if (( $+functions[$fn] )); then
        "$fn" "$1" "$AI_PROMPT_SYSTEM_PROMPT"
    else
        echo "ai-prompt: unknown backend '$AI_PROMPT_BACKEND'" >&2
    fi
}

# -- Custom keymap --
# Inherits all bindings from main so normal editing works in AI mode.
bindkey -N ai-prompt main
bindkey -M ai-prompt '^M'    _ai_prompt_submit   # Enter
bindkey -M ai-prompt '^['    _ai_prompt_cancel    # Escape (standalone, after KEYTIMEOUT)
bindkey -M ai-prompt '^[^['  _ai_prompt_cancel    # Double-Escape (instant cancel)
bindkey -M ai-prompt '^C'    _ai_prompt_cancel    # Ctrl-C

# -- POSTDISPLAY persistence --
# zsh-autosuggestions clears POSTDISPLAY on buffer changes. This hook restores
# it while AI mode is active so the indicator stays visible during typing.
_ai_prompt_pre_redraw() {
    if (( _AI_PROMPT_ACTIVE && ! _AI_PROMPT_WAITING )); then
        POSTDISPLAY=$'\n'"  ⟡ AI mode — Enter to send, Esc to cancel"
    fi
}
autoload -Uz add-zle-hook-widget
add-zle-hook-widget zle-line-pre-redraw _ai_prompt_pre_redraw

# -- Spinner via TRAPALRM --
_ai_prompt_trapalrm() {
    (( _AI_PROMPT_WAITING )) || return
    _AI_PROMPT_SPINNER_IDX=$(( (_AI_PROMPT_SPINNER_IDX + 1) % ${#_AI_PROMPT_SPINNER_FRAMES} ))
    POSTDISPLAY=$'\n'"  ${_AI_PROMPT_SPINNER_FRAMES[$_AI_PROMPT_SPINNER_IDX+1]} thinking..."
    zle reset-prompt
}

# -- Widgets --

_ai_prompt_activate() {
    # Ignore if already active or waiting for a response.
    (( _AI_PROMPT_ACTIVE || _AI_PROMPT_WAITING )) && return

    # Save current state.
    _AI_PROMPT_SAVED_BUFFER="$BUFFER"
    _AI_PROMPT_SAVED_CURSOR=$CURSOR
    _AI_PROMPT_ACTIVE=1
    _AI_PROMPT_WAITING=0

    # Clear buffer for query input.
    BUFFER=''
    CURSOR=0
    POSTDISPLAY=$'\n'"  ⟡ AI mode — Enter to send, Esc to cancel"

    # Switch to AI keymap.
    zle -K ai-prompt
    zle reset-prompt
}
zle -N _ai_prompt_activate

_ai_prompt_submit() {
    local query="$BUFFER"

    # Nothing to submit.
    if [[ -z "$query" ]]; then
        _ai_prompt_cancel
        return
    fi

    # Enter waiting state.
    _AI_PROMPT_WAITING=1
    _AI_PROMPT_SPINNER_IDX=0
    BUFFER=''
    CURSOR=0
    POSTDISPLAY=$'\n'"  ${_AI_PROMPT_SPINNER_FRAMES[1]} thinking..."

    # Save and set TMOUT for spinner ticks.
    _AI_PROMPT_SAVED_TMOUT="${TMOUT:-0}"
    TMOUT=1

    # Install our TRAPALRM (save any existing one).
    functions[_ai_prompt_saved_trapalrm]="$functions[TRAPALRM]"
    TRAPALRM() { _ai_prompt_trapalrm; }

    zle reset-prompt

    # Launch async API call.
    exec {_AI_PROMPT_FD}< <(
        _ai_prompt_query "$query" 2>/dev/null
    )
    zle -F -w "$_AI_PROMPT_FD" _ai_prompt_handler
}
zle -N _ai_prompt_submit

_ai_prompt_cancel() {
    # Restore original buffer.
    BUFFER="$_AI_PROMPT_SAVED_BUFFER"
    CURSOR=$_AI_PROMPT_SAVED_CURSOR

    # Kill pending async call if any.
    if [[ -n "$_AI_PROMPT_FD" ]]; then
        zle -F "$_AI_PROMPT_FD" 2>/dev/null
        exec {_AI_PROMPT_FD}<&- 2>/dev/null
        _AI_PROMPT_FD=''
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
    _AI_PROMPT_FD=''

    if [[ -n "$result" ]]; then
        BUFFER="$result"
        CURSOR=${#BUFFER}
    else
        # On error or empty response, restore original buffer.
        BUFFER="$_AI_PROMPT_SAVED_BUFFER"
        CURSOR=$_AI_PROMPT_SAVED_CURSOR
    fi

    _ai_prompt_cleanup
    zle -R
}
zle -N _ai_prompt_handler

# -- Cleanup helper --
_ai_prompt_cleanup() {
    _AI_PROMPT_ACTIVE=0
    _AI_PROMPT_WAITING=0
    POSTDISPLAY=''

    # Restore TMOUT and TRAPALRM.
    TMOUT="${_AI_PROMPT_SAVED_TMOUT}"
    if (( $+functions[_ai_prompt_saved_trapalrm] )); then
        functions[TRAPALRM]="$functions[_ai_prompt_saved_trapalrm]"
        unfunction _ai_prompt_saved_trapalrm 2>/dev/null
    else
        unfunction TRAPALRM 2>/dev/null
    fi

    # Switch back to main keymap.
    zle -K main
    zle reset-prompt
}

# -- Bind the activation key --
bindkey "$AI_PROMPT_KEYBINDING" _ai_prompt_activate
