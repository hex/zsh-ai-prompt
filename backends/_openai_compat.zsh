# ABOUTME: Shared helper for OpenAI-compatible chat completions APIs.
# ABOUTME: Used by openai and gemini backends to avoid duplicating curl+jq logic.

_ai_prompt_query_openai_compat() {
    local url="$1" api_key="$2" model="$3" query="$4" system="$5"

    if [[ -z "$api_key" ]]; then
        echo "ai-prompt: API key not set" >&2
        return 1
    fi

    local messages='[]'
    if [[ -n "$system" ]]; then
        messages=$(jq -n --arg s "$system" '[{"role":"system","content":$s}]')
    fi
    messages=$(echo "$messages" | jq --arg q "$query" '. + [{"role":"user","content":$q}]')

    local body
    body=$(jq -n \
        --arg model "$model" \
        --argjson msgs "$messages" \
        '{model:$model, messages:$msgs}')

    curl -sS "$url" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d "$body" \
    | jq -r '.choices[0].message.content // empty'
}
