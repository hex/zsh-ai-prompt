# ABOUTME: Claude backend for ai-prompt.
# ABOUTME: Uses the Anthropic Messages API if available, falls back to the `claude` CLI.

source "${0:A:h}/_http.zsh"

_ai_prompt_claude_api_key() {
    print -r -- "${ZSH_AI_PROMPT_API_KEY:-$ANTHROPIC_API_KEY}"
}

# The API and the CLI name models differently, so the default depends on
# which one the query will use.
_ai_prompt_model_claude() {
    if [[ -n "$(_ai_prompt_claude_api_key)" ]]; then
        print -r -- "${ZSH_AI_PROMPT_MODEL:-claude-haiku-5-5}"
    else
        print -r -- "${ZSH_AI_PROMPT_MODEL:-haiku}"
    fi
}

_ai_prompt_query_claude_api() {
    local query="$1" system="$2" api_key="$3"
    local api_url="${ZSH_AI_PROMPT_API_URL:-https://api.anthropic.com/v1/messages}"

    local body
    body=$(jq -n \
        --arg model "$(_ai_prompt_model_claude)" \
        --arg query "$query" \
        '{model:$model, max_tokens:1024, messages:[{role:"user",content:$query}]}')

    if [[ -n "$system" ]]; then
        body=$(echo "$body" | jq --arg s "$system" '. + {system:$s}')
    fi

    local response
    response=$(print -r -- "$body" | _ai_prompt_post_json "$api_url" \
        "x-api-key: $api_key" \
        "anthropic-version: 2023-06-01") || return 1
    print -r -- "$response" | jq -r '.content[0].text // empty'
}

# Runs the CLI as a plain model call: no tools, no user/project settings
# (hooks, plugins, MCP servers), no skills and no saved session. The query
# goes through stdin so it stays off the process list.
_ai_prompt_query_claude_cli() {
    local query="$1" system="$2"
    local -a cmd=(claude --print
        --tools ''
        --setting-sources ''
        --strict-mcp-config
        --disable-slash-commands
        --no-session-persistence
        --model "$(_ai_prompt_model_claude)")
    [[ -n "$system" ]] && cmd+=(--system-prompt "$system")
    print -r -- "$query" | "${cmd[@]}"
}

_ai_prompt_query_claude() {
    local query="$1" system="$2"
    local api_key="$(_ai_prompt_claude_api_key)"

    if [[ -n "$api_key" ]]; then
        _ai_prompt_query_claude_api "$query" "$system" "$api_key"
    elif (( ZSH_AI_PROMPT_USE_CLI )) && (( $+commands[claude] )); then
        _ai_prompt_query_claude_cli "$query" "$system"
    else
        echo "ai-prompt: ANTHROPIC_API_KEY not set and claude CLI not found" >&2
        return 1
    fi
}
