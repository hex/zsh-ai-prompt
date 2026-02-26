# ABOUTME: OpenAI-compatible backend for ai-prompt.
# ABOUTME: Uses curl + jq. Works with any OpenAI-compatible API (OpenAI, Azure, etc.).

: ${AI_PROMPT_API_URL:=https://api.openai.com/v1/chat/completions}
: ${AI_PROMPT_MODEL:=gpt-4o}

_ai_prompt_query_openai() {
    local query="$1" system="$2"

    if [[ -z "$AI_PROMPT_API_KEY" ]]; then
        echo "ai-prompt: AI_PROMPT_API_KEY not set" >&2
        return 1
    fi

    local messages='[]'
    if [[ -n "$system" ]]; then
        messages=$(jq -n --arg s "$system" '[{"role":"system","content":$s}]')
    fi
    messages=$(echo "$messages" | jq --arg q "$query" '. + [{"role":"user","content":$q}]')

    local body
    body=$(jq -n \
        --arg model "$AI_PROMPT_MODEL" \
        --argjson msgs "$messages" \
        '{model:$model, messages:$msgs}')

    curl -sS "$AI_PROMPT_API_URL" \
        -H "Authorization: Bearer $AI_PROMPT_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$body" \
    | jq -r '.choices[0].message.content // empty'
}
