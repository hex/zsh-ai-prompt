# ABOUTME: Ollama backend for ai-prompt.
# ABOUTME: Queries a local Ollama instance via its REST API.

source "${0:A:h}/_http.zsh"

: ${ZSH_AI_PROMPT_OLLAMA_URL:=http://localhost:11434}

_ai_prompt_model_ollama() {
    print -r -- "${ZSH_AI_PROMPT_MODEL:-llama3}"
}

_ai_prompt_query_ollama() {
    local query="$1" system="$2"
    local prompt="$query"
    [[ -n "$system" ]] && prompt="$system"$'\n\n'"$query"

    local response
    response=$(jq -n --arg model "$(_ai_prompt_model_ollama)" --arg prompt "$prompt" \
            '{model:$model, prompt:$prompt, stream:false}' \
        | _ai_prompt_post_json "$ZSH_AI_PROMPT_OLLAMA_URL/api/generate") || return 1
    print -r -- "$response" | jq -r '.response // empty'
}
