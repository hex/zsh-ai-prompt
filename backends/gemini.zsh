# ABOUTME: Google Gemini backend for ai-prompt.
# ABOUTME: Uses `gemini` CLI if available, falls back to the Gemini API.

source "${0:A:h}/_openai_compat.zsh"

_ai_prompt_query_gemini_api() {
    local query="$1" system="$2"
    local api_key="${ZSH_AI_PROMPT_API_KEY:-$GEMINI_API_KEY}"
    local api_url="${ZSH_AI_PROMPT_API_URL:-https://generativelanguage.googleapis.com/v1beta/openai/chat/completions}"
    local model="${ZSH_AI_PROMPT_MODEL:-${GEMINI_MODEL:-gemini-2.5-flash-lite}}"

    _ai_prompt_query_openai_compat "$api_url" "$api_key" "$model" "$query" "$system"
}

_ai_prompt_query_gemini() {
    local query="$1" system="$2"
    local api_key="${ZSH_AI_PROMPT_API_KEY:-$GEMINI_API_KEY}"

    if [[ -n "$api_key" ]]; then
        _ai_prompt_query_gemini_api "$query" "$system"
    elif (( ZSH_AI_PROMPT_USE_CLI )) && (( $+commands[gemini] )); then
        local prompt="$query"
        [[ -n "$system" ]] && prompt="$system\n\n$query"
        gemini -p "$prompt" -m "${ZSH_AI_PROMPT_MODEL:-${GEMINI_MODEL:-gemini-2.5-flash-lite}}" -o text 2>/dev/null
    else
        echo "ai-prompt: gemini CLI not found and GEMINI_API_KEY not set" >&2
        return 1
    fi
}
