# ABOUTME: OpenAI backend for ai-prompt.
# ABOUTME: Uses the OpenAI chat completions API via shared OpenAI-compatible helper.

source "${0:A:h}/_openai_compat.zsh"

_ai_prompt_model_openai() {
    print -r -- "${ZSH_AI_PROMPT_MODEL:-gpt-6-luna}"
}

_ai_prompt_query_openai() {
    local query="$1" system="$2"
    local api_key="${ZSH_AI_PROMPT_API_KEY:-$OPENAI_API_KEY}"
    local api_url="${ZSH_AI_PROMPT_API_URL:-https://api.openai.com/v1/chat/completions}"

    _ai_prompt_query_openai_compat "$api_url" "$api_key" "$(_ai_prompt_model_openai)" "$query" "$system"
}
