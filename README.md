# zsh-ai-prompt

Zsh plugin that provides an inline AI query mode via ZLE widgets. Press a keybinding to enter AI mode, type a natural language query, and get a shell command back in your buffer — ready to edit or execute.

## Installation

### Oh My Zsh

```bash
git clone https://github.com/hex/zsh-ai-prompt.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-ai-prompt
```

Add `zsh-ai-prompt` to your plugins in `~/.zshrc`:

```bash
plugins=(... zsh-ai-prompt)
```

### Zinit

```bash
zinit light hex/zsh-ai-prompt
```

### Antidote

Add to `~/.zsh_plugins.txt`:

```
hex/zsh-ai-prompt
```

### Antigen

```bash
antigen bundle hex/zsh-ai-prompt
```

### Manual

Clone the repo and source the plugin in your `~/.zshrc`:

```bash
git clone https://github.com/hex/zsh-ai-prompt.git ~/.zsh/zsh-ai-prompt
source ~/.zsh/zsh-ai-prompt/zsh-ai-prompt.plugin.zsh
```

## Usage

1. Press **Alt-A** (default) to enter AI mode
2. Type your query in plain English (e.g., "find all .log files older than 7 days")
3. Press **Enter** to submit — a spinner animates while the AI responds
4. The AI's response replaces your buffer — press Enter to execute, or edit first
5. Press **Escape** or **Ctrl-C** to cancel at any time

## Configuration

Works out of the box with the `claude` CLI installed — no configuration needed. For other backends, set `ZSH_AI_PROMPT_BACKEND` and have the provider's API key in your environment.

All settings are optional and can be set in your `.zshrc` before the plugin loads:

```bash
# Backend: claude (default), openai, gemini, ollama
ZSH_AI_PROMPT_BACKEND="gemini"

# Keybinding (default: Alt-A)
ZSH_AI_PROMPT_KEYBINDING="^[a"

# System prompt sent with every query
ZSH_AI_PROMPT_SYSTEM_PROMPT="Respond with only the command(s), no explanation."

# Visual styling (region_highlight format)
ZSH_AI_PROMPT_SYMBOL_STYLE="fg=magenta"
ZSH_AI_PROMPT_TEXT_STYLE="fg=242"
```

## Backends

### Claude (default)

Uses the `claude` CLI if available (`claude --print`), otherwise falls back to the Anthropic Messages API with `ANTHROPIC_API_KEY`.

```bash
ZSH_AI_PROMPT_BACKEND="claude"
# With CLI installed: works with zero config, uses existing CLI auth
ZSH_AI_PROMPT_MODEL="sonnet"  # override CLI model (default: haiku)

# Without CLI: auto-detects $ANTHROPIC_API_KEY, or set explicitly:
# ZSH_AI_PROMPT_API_KEY="sk-ant-..."
# ZSH_AI_PROMPT_MODEL="claude-haiku-4-5"  # default (alias, always latest)
```

### OpenAI

Auto-detects `OPENAI_API_KEY` from your environment. Works with any OpenAI-compatible API.

```bash
ZSH_AI_PROMPT_BACKEND="openai"
# Uses $OPENAI_API_KEY automatically, or set explicitly:
# ZSH_AI_PROMPT_API_KEY="sk-..."
# ZSH_AI_PROMPT_MODEL="gpt-4.1-nano"     # default
# ZSH_AI_PROMPT_API_URL="https://..."    # for compatible APIs
```

### Gemini

Auto-detects `GEMINI_API_KEY` from your environment. Uses Gemini's OpenAI-compatible endpoint.

```bash
ZSH_AI_PROMPT_BACKEND="gemini"
# Uses $GEMINI_API_KEY automatically, or set explicitly:
# ZSH_AI_PROMPT_API_KEY="..."
# ZSH_AI_PROMPT_MODEL="gemini-2.5-flash-lite"  # default, or uses $GEMINI_MODEL
```

### Ollama

Queries a local Ollama instance. No API key needed.

```bash
ZSH_AI_PROMPT_BACKEND="ollama"
# ZSH_AI_PROMPT_MODEL="llama3"                          # default
# ZSH_AI_PROMPT_OLLAMA_URL="http://localhost:11434"      # default
```

## Dependencies

- **zsh** 4.2.0+ (for PREDISPLAY support)
- **jq** (for openai, gemini, and ollama backends)
- **curl** (for openai, gemini, and ollama backends)
- **claude CLI** or **ANTHROPIC_API_KEY** (for claude backend — one or the other)
