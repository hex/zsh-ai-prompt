# ABOUTME: Shared HTTP helper for the API backends: POSTs a JSON body and returns the response.
# ABOUTME: Keeps keys and prompts off the process list and reports HTTP and network errors.

# Usage: print -r -- "$json" | _ai_prompt_post_json <url> [header...]
# The body is read from stdin and headers from a file descriptor, so neither
# appears in `ps`. Prints the response body on success. On a network error,
# timeout or HTTP error status, prints an "ai-prompt: ..." message on stderr
# and returns 1.
_ai_prompt_post_json() {
    local url="$1"; shift
    local meta_marker='__ai_prompt_http__'

    local out
    out=$(curl -s \
        --max-time "$ZSH_AI_PROMPT_TIMEOUT" \
        -w "\n$meta_marker %{http_code} %{errormsg}" \
        -H @<(print -rl -- "$@" "Content-Type: application/json") \
        --data-binary @- \
        "$url")

    local meta="${out##*$'\n'$meta_marker }"
    local body="${out%$'\n'$meta_marker *}"
    local http_code="${meta%% *}" curl_error="${meta#* }"

    if [[ "$http_code" == 000 ]]; then
        echo "ai-prompt: request to $url failed: ${curl_error:-no response}" >&2
        return 1
    fi

    if (( http_code >= 400 )); then
        local api_message
        api_message=$(print -r -- "$body" | jq -r '
            (if type == "array" then .[0] else . end)
            | .error
            | if type == "object" then .message else . end
            // empty' 2>/dev/null)
        echo "ai-prompt: HTTP $http_code: ${api_message:-${body[1,300]}}" >&2
        return 1
    fi

    print -r -- "$body"
}
