# ai-prompt

Zsh plugin that provides an inline AI query mode via ZLE widgets. Press a keybinding to enter AI mode, type a natural language query, and get a shell command back in your buffer — ready to edit or execute.

## Installation

### Oh My Zsh

Clone into your custom plugins directory:

```bash
git clone <repo-url> ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/ai-prompt
```

Add to your `.zshrc`:

```bash
plugins=(... ai-prompt)
```

### Manual

Source the plugin from your `.zshrc`:

```bash
source /path/to/ai-prompt/ai-prompt.plugin.zsh
```

## Usage

1. Press **Alt-A** (default) to enter AI mode
2. Type your query in plain English (e.g., "find all .log files older than 7 days")
3. Press **Enter** to submit — a spinner animates while the AI responds
4. The AI's response replaces your buffer — press Enter to execute, or edit first
5. Press **Escape** or **Ctrl-C** to cancel at any time

## Configuration

Set these variables in your `.zshrc` **before** the plugin loads:

```bash
# Backend: claude (default), openai, gemini, ollama
AI_PROMPT_BACKEND="claude"

# Keybinding (default: Alt-A)
AI_PROMPT_KEYBINDING="^[a"

# System prompt sent with every query
AI_PROMPT_SYSTEM_PROMPT="Respond with only the command(s), no explanation."

# Visual styling (region_highlight format)
AI_PROMPT_SYMBOL_STYLE="fg=magenta"
AI_PROMPT_TEXT_STYLE="fg=242"
```

## Backends

### Claude (default)

Uses the `claude` CLI if available (`claude --print`), otherwise falls back to the Anthropic Messages API with `ANTHROPIC_API_KEY`.

```bash
AI_PROMPT_BACKEND="claude"
# With CLI installed: uses existing CLI auth, no API key needed
AI_PROMPT_MODEL="sonnet"  # CLI model names

# Without CLI: auto-detects $ANTHROPIC_API_KEY, or set explicitly:
# AI_PROMPT_API_KEY="sk-ant-..."
# AI_PROMPT_MODEL="claude-sonnet-4-20250514"  # API model IDs
```

### OpenAI

Auto-detects `OPENAI_API_KEY` from your environment. Works with any OpenAI-compatible API.

```bash
AI_PROMPT_BACKEND="openai"
# Uses $OPENAI_API_KEY automatically, or set explicitly:
# AI_PROMPT_API_KEY="sk-..."
# AI_PROMPT_MODEL="gpt-4o"           # default
# AI_PROMPT_API_URL="https://..."    # for compatible APIs
```

### Gemini

Auto-detects `GEMINI_API_KEY` from your environment. Uses Gemini's OpenAI-compatible endpoint.

```bash
AI_PROMPT_BACKEND="gemini"
# Uses $GEMINI_API_KEY automatically, or set explicitly:
# AI_PROMPT_API_KEY="..."
# AI_PROMPT_MODEL="gemini-2.0-flash"  # default, or uses $GEMINI_MODEL
```

### Ollama

Queries a local Ollama instance. No API key needed.

```bash
AI_PROMPT_BACKEND="ollama"
# AI_PROMPT_MODEL="llama3"                          # default
# AI_PROMPT_OLLAMA_URL="http://localhost:11434"      # default
```

## Dependencies

- **zsh** 4.2.0+ (for PREDISPLAY support)
- **jq** (for openai, gemini, and ollama backends)
- **curl** (for openai, gemini, and ollama backends)
- **claude CLI** or **ANTHROPIC_API_KEY** (for claude backend — one or the other)
