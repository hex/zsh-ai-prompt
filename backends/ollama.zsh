# ABOUTME: Ollama backend for ai-prompt.
# ABOUTME: Queries a local Ollama instance via its REST API.

: ${AI_PROMPT_OLLAMA_URL:=http://localhost:11434}
: ${AI_PROMPT_MODEL:=llama3}

_ai_prompt_query_ollama() {
    local query="$1" system="$2"
    local prompt="$query"
    [[ -n "$system" ]] && prompt="$system\n\n$query"

    curl -sS "$AI_PROMPT_OLLAMA_URL/api/generate" \
        -d "$(jq -n --arg model "$AI_PROMPT_MODEL" --arg prompt "$prompt" \
            '{model:$model, prompt:$prompt, stream:false}')" \
    | jq -r '.response // empty'
}
