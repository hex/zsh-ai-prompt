# ABOUTME: Claude CLI backend for ai-prompt.
# ABOUTME: Uses `claude --print` for non-interactive single-shot queries.

_ai_prompt_query_claude() {
    local query="$1" system="$2"
    local -a cmd=(claude --print)
    [[ -n "$system" ]] && cmd+=(--system-prompt "$system")
    [[ -n "$AI_PROMPT_MODEL" ]] && cmd+=(--model "$AI_PROMPT_MODEL")
    cmd+=("$query")
    "${cmd[@]}" 2>/dev/null
}
