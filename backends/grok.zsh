# ABOUTME: xAI Grok backend for ai-prompt.
# ABOUTME: Uses xAI's OpenAI-compatible chat completions API via the shared helper.

source "${0:A:h}/_openai_compat.zsh"

_ai_prompt_model_grok() {
    print -r -- "${ZSH_AI_PROMPT_MODEL:-grok-4.7}"
}

_ai_prompt_query_grok() {
    local query="$1" system="$2"
    local api_key="${ZSH_AI_PROMPT_API_KEY:-$XAI_API_KEY}"
    local api_url="${ZSH_AI_PROMPT_API_URL:-https://api.x.ai/v1/chat/completions}"

    _ai_prompt_query_openai_compat "$api_url" "$api_key" "$(_ai_prompt_model_grok)" "$query" "$system"
}
