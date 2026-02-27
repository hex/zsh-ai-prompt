# ABOUTME: Claude backend for ai-prompt.
# ABOUTME: Uses `claude` CLI if available, falls back to the Anthropic Messages API.

_ai_prompt_query_claude_api() {
    local query="$1" system="$2"
    local api_key="${ZSH_AI_PROMPT_API_KEY:-$ANTHROPIC_API_KEY}"
    local api_url="${ZSH_AI_PROMPT_API_URL:-https://api.anthropic.com/v1/messages}"
    local model="${ZSH_AI_PROMPT_MODEL:-claude-haiku-4-5}"

    if [[ -z "$api_key" ]]; then
        echo "ai-prompt: claude CLI not found and ANTHROPIC_API_KEY not set" >&2
        return 1
    fi

    local body
    body=$(jq -n \
        --arg model "$model" \
        --arg query "$query" \
        '{model:$model, max_tokens:1024, messages:[{role:"user",content:$query}]}')

    if [[ -n "$system" ]]; then
        body=$(echo "$body" | jq --arg s "$system" '. + {system:$s}')
    fi

    curl -sS "$api_url" \
        -H "x-api-key: $api_key" \
        -H "anthropic-version: 2023-06-01" \
        -H "Content-Type: application/json" \
        -d "$body" \
    | jq -r '.content[0].text // empty'
}

_ai_prompt_query_claude() {
    local query="$1" system="$2"

    if (( $+commands[claude] )); then
        local -a cmd=(claude --print)
        [[ -n "$system" ]] && cmd+=(--system-prompt "$system")
        cmd+=(--model "${ZSH_AI_PROMPT_MODEL:-haiku}")
        cmd+=("$query")
        "${cmd[@]}" 2>/dev/null
    else
        _ai_prompt_query_claude_api "$query" "$system"
    fi
}
