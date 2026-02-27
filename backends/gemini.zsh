# ABOUTME: Google Gemini backend for ai-prompt.
# ABOUTME: Uses Gemini's OpenAI-compatible chat completions endpoint.

source "${0:A:h}/_openai_compat.zsh"

_ai_prompt_query_gemini() {
    local query="$1" system="$2"
    local api_key="${ZSH_AI_PROMPT_API_KEY:-$GEMINI_API_KEY}"
    local api_url="${ZSH_AI_PROMPT_API_URL:-https://generativelanguage.googleapis.com/v1beta/openai/chat/completions}"
    local model="${ZSH_AI_PROMPT_MODEL:-${GEMINI_MODEL:-gemini-2.5-flash-lite}}"

    _ai_prompt_query_openai_compat "$api_url" "$api_key" "$model" "$query" "$system"
}
