# ABOUTME: Google Gemini backend for ai-prompt.
# ABOUTME: Uses the Gemini API if available, falls back to the `gemini` CLI.

source "${0:A:h}/_openai_compat.zsh"

_ai_prompt_model_gemini() {
    print -r -- "${ZSH_AI_PROMPT_MODEL:-${GEMINI_MODEL:-gemini-flash-lite-latest}}"
}

_ai_prompt_query_gemini_api() {
    local query="$1" system="$2" api_key="$3"
    local api_url="${ZSH_AI_PROMPT_API_URL:-https://generativelanguage.googleapis.com/v1beta/openai/chat/completions}"

    _ai_prompt_query_openai_compat "$api_url" "$api_key" "$(_ai_prompt_model_gemini)" "$query" "$system"
}

_ai_prompt_query_gemini() {
    local query="$1" system="$2"
    local api_key="${ZSH_AI_PROMPT_API_KEY:-$GEMINI_API_KEY}"

    if [[ -n "$api_key" ]]; then
        _ai_prompt_query_gemini_api "$query" "$system" "$api_key"
    elif (( ZSH_AI_PROMPT_USE_CLI )) && (( $+commands[gemini] )); then
        local prompt="$query"
        [[ -n "$system" ]] && prompt="$system"$'\n\n'"$query"
        gemini -p "$prompt" -m "$(_ai_prompt_model_gemini)" -o text
    else
        echo "ai-prompt: gemini CLI not found and GEMINI_API_KEY not set" >&2
        return 1
    fi
}
