#!/usr/bin/env python3
# ABOUTME: Generates assets/how-it-works.svg, the animated README demo of zsh-ai-prompt.
# ABOUTME: Usage: python3 assets/gen-how-it-works-svg.py assets/how-it-works.svg. Pure SMIL, loops forever.

import sys
from dataclasses import dataclass
from html import escape

CW = 15.6         # monospace advance at font-size 26 (0.6em)
X_BUF = 34        # buffer start after "❯ "
# The indicator glyph (⟡, or the spinner while waiting) and its label sit at
# the same columns in every phase. Placed explicitly because renderers draw
# leading spaces at varying widths.
X_GLYPH = X_BUF
X_LABEL = round(X_BUF + 2.1 * CW, 1)

MODEL = "claude-haiku-5-5"
# Real claude-haiku-5-5 answers to these requests with the default system prompt.
EXAMPLES = [
    ("find all .log files older than 7 days", 'find . -name "*.log" -type f -mtime +7'),
    ("kill whatever is listening on port 3000", "lsof -ti :3000 | xargs kill -9"),
]

CHAR = 0.065      # seconds per typed character


@dataclass(frozen=True)
class Cycle:
    """One example's timeline, in seconds from the start of the loop."""
    query: str
    answer: str
    start: float
    alt: float        # Alt-A pressed
    typing: float     # first character typed
    enter: float      # Enter pressed
    reply: float      # answer replaces the buffer
    end: float        # end of the hold on the answer


def make_cycle(start, query, answer):
    alt = start + 1.0
    typing = alt + 0.7
    enter = typing + CHAR * len(query) + 0.5
    reply = enter + 1.7
    return Cycle(query, answer, start, alt, typing, enter, reply, reply + 3.2)


CYCLES = []
for query, answer in EXAMPLES:
    CYCLES.append(make_cycle(CYCLES[-1].end if CYCLES else 0.0, query, answer))
T = round(CYCLES[-1].end + 0.3, 2)   # loop length in seconds

INK, MUTED, FAINT = "#4F4D48", "#9A94A8", "#E2DECE"
PROMPT_GREEN, DIR_BLUE, MAGENTA, ACCENT = "#4E9A06", "#0087AF", "#B03A9E", "#D97757"
ROW_B, ROW_C = 150, 196


def kt(t):
    return f"{t / T:.4f}".rstrip("0").rstrip(".") or "0"


def visible(*spans):
    """Discrete opacity animation: 1 inside the (start, end) spans, 0 elsewhere."""
    points = [(0.0, "0")]
    for start, end in spans:
        points += [(start, "1"), (end, "0")]
    if points[1][0] == 0.0:
        points = points[1:]
    return steps("opacity", points)


def steps(attr, points):
    """Discrete animation of any attribute through (time, value) points."""
    values = ";".join(str(v) for _, v in points)
    times = ";".join(kt(t) for t, _ in points)
    return (f'<animate attributeName="{attr}" dur="{T}s" repeatCount="indefinite" '
            f'calcMode="discrete" values="{values}" keyTimes="{times}"/>')


def fixed_width(chars):
    """Pins a line to CW per character, so the typing clip and the cursor
    line up even when the viewer's monospace font has a different advance."""
    return f' textLength="{chars * CW:.1f}" lengthAdjust="spacingAndGlyphs"'


def text(x, y, s, fill, extra=""):
    return f'<text x="{x}" y="{y}" fill="{fill}"{extra}>{escape(s)}</text>'


def typed_points(c):
    return [(c.typing + i * CHAR, round((i + 1) * CW, 1)) for i in range(len(c.query))]


# typed query: per example, a clip that widens one character at a time
clips = "".join(
    f'<clipPath id="typed{i}"><rect x="0" y="{ROW_C - 30}" width="0" height="40">'
    f'{steps("width", [(0.0, 0)] + typed_points(c))}</rect></clipPath>'
    for i, c in enumerate(CYCLES))

# cursor: on the prompt line, then the query line in AI mode, then after the answer
cursor_x, cursor_y = [], []
for c in CYCLES:
    cursor_x += [(c.start, X_BUF), (c.alt + 0.2, 0)] + typed_points(c) + \
                [(c.enter, 0), (c.reply, round(X_BUF + len(c.answer) * CW + 4, 1))]
    cursor_y += [(c.start, ROW_B - 24), (c.alt + 0.2, ROW_C - 24), (c.reply, ROW_B - 24)]

SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
spin_dur = 0.8
spinner_glyphs = []
for i, g in enumerate(SPINNER):
    a, b = i / len(SPINNER), (i + 1) / len(SPINNER)
    vals, times = ("1;0", f"0;{b:.2f}") if i == 0 else ("0;1;0", f"0;{a:.2f};{b:.2f}")
    spinner_glyphs.append(
        f'<text x="{X_GLYPH}" y="{ROW_B}" fill="{MAGENTA}" opacity="0">{g}'
        f'<animate attributeName="opacity" dur="{spin_dur}s" repeatCount="indefinite" '
        f'calcMode="discrete" values="{vals}" keyTimes="{times}"/></text>')

indicator_text = f"AI mode ({MODEL}) — Enter to send, Esc to cancel"
caption_texts = [
    "Alt-A opens AI mode",
    "ask for what you want in plain English",
    "Enter sends it to Claude, OpenAI, Gemini, Grok or Ollama",
    "the command lands in your buffer: Enter runs it, or edit it first",
]
caption_spans = [
    [(c.alt, c.typing) for c in CYCLES],
    [(c.typing, c.enter) for c in CYCLES],
    [(c.enter, c.reply) for c in CYCLES],
    [(c.reply, c.end - 0.3) for c in CYCLES],
]
chips = [("⌥ A", 112, [(c.alt, c.alt + 1.1) for c in CYCLES]),
         ("⏎ Enter", 150, [(c.enter, c.enter + 0.9) for c in CYCLES])]
last = len(CYCLES) - 1

queries = "".join(f"""
      <g opacity="0" clip-path="url(#typed{i})">{visible((c.typing, c.enter))}
        {text(0, ROW_C, c.query, INK, fixed_width(len(c.query)))}
      </g>""" for i, c in enumerate(CYCLES))

# The last answer has base opacity 1, so a renderer without SMIL still shows
# a finished state.
answers = "".join(f"""
      <g opacity="{1 if i == last else 0}">{visible((c.reply, c.end - 0.3))}
        {text(X_BUF, ROW_B, c.answer, INK, fixed_width(len(c.answer)))}
      </g>""" for i, c in enumerate(CYCLES))

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" xml:space="preserve" style="white-space:pre" viewBox="0 0 1536 404" width="100%" role="img" aria-label="A terminal, twice: Alt-A opens AI mode, the user types a request in plain English, presses Enter, a spinner runs, and a shell command replaces the request in the buffer, ready to run" font-family="'SF Mono', Menlo, Consolas, 'DejaVu Sans Mono', monospace" font-size="26">
  <!-- Generated by assets/gen-how-it-works-svg.py; edit that and regenerate. -->
  <title>zsh-ai-prompt: how it works</title>
  <defs>
    {clips}
    <filter id="soft" x="-5%" y="-20%" width="110%" height="140%">
      <feDropShadow dx="0" dy="10" stdDeviation="18" flood-color="#2B2640" flood-opacity="0.12"/>
    </filter>
  </defs>

  <!-- no page background: the window sits on whatever the README renders on -->
  <g transform="translate(96,24)">
    <rect width="1344" height="352" rx="18" fill="#F8F5F1" stroke="{FAINT}" stroke-width="2" filter="url(#soft)"/>
    <circle cx="30" cy="28" r="7" fill="{FAINT}"/>
    <circle cx="54" cy="28" r="7" fill="{FAINT}"/>
    <circle cx="78" cy="28" r="7" fill="{FAINT}"/>

    <g transform="translate(40,0)">
      <!-- powerlevel10k-style two-line prompt -->
      {text(0, 104, "~/projects/api", DIR_BLUE)}
      {text(round(15 * CW, 1), 104, "main", PROMPT_GREEN)}
      {text(0, ROW_B, "❯", PROMPT_GREEN, ' font-weight="700"')}

      <!-- AI mode indicator (PREDISPLAY), between Alt-A and Enter -->
      <g opacity="0">{visible(*[(c.alt + 0.2, c.enter) for c in CYCLES])}
        {text(X_GLYPH, ROW_B, "⟡", MAGENTA)}
        {text(X_LABEL, ROW_B, indicator_text, MUTED, fixed_width(len(indicator_text)))}
      </g>

      <!-- the request, typed on the line below the indicator -->{queries}

      <!-- waiting: spinner in the indicator line -->
      <g opacity="0">{visible(*[(c.enter, c.reply) for c in CYCLES])}
        {"".join(spinner_glyphs)}
        {text(X_LABEL, ROW_B, "thinking...", MUTED)}
      </g>

      <!-- the answer replaces the buffer, right after the prompt -->{answers}

      <!-- block cursor: moves with the buffer, blinks -->
      <g opacity="0">{visible(*[(c.start, c.end - 0.3) for c in CYCLES])}
        <rect width="14" height="30" fill="{INK}" opacity="0.8">
          {steps("x", cursor_x)}
          {steps("y", cursor_y)}
          <animate attributeName="opacity" values="0.8;0.8;0;0" keyTimes="0;0.5;0.5;1" dur="1s" repeatCount="indefinite"/>
        </rect>
      </g>
    </g>

    <!-- key presses -->
    {"".join(f"""<g opacity="0">{visible(*spans)}
      <rect x="{1344 - 40 - w}" y="166" width="{w}" height="46" rx="10" fill="#FFFFFF" stroke="{FAINT}" stroke-width="2"/>
      <rect x="{1344 - 40 - w}" y="206" width="{w}" height="6" rx="3" fill="{FAINT}"/>
      <text x="{1344 - 40 - w / 2}" y="197" fill="{INK}" font-size="22" text-anchor="middle">{escape(label)}</text>
    </g>
    """ for label, w, spans in chips)}

    <!-- what is happening, one step at a time -->
    <line x1="40" y1="246" x2="1304" y2="246" stroke="{FAINT}" stroke-width="2"/>
    {"".join(f"""<g opacity="{1 if n == len(caption_texts) else 0}" font-size="22">{visible(*spans)}
      <circle cx="54" cy="294" r="15" fill="{ACCENT}"/>
      <text x="54" y="301" fill="#FFFFFF" font-size="18" font-weight="700" text-anchor="middle">{n}</text>
      <text x="84" y="302" fill="{INK}">{escape(caption)}</text>
    </g>
    """ for n, (caption, spans) in enumerate(zip(caption_texts, caption_spans), 1))}
  </g>
</svg>
'''

with open(sys.argv[1], "w") as f:
    f.write(svg)
answers_at = ", ".join(f'{c.reply:.2f}s' for c in CYCLES)
print(f"wrote {sys.argv[1]} ({len(svg)} bytes), loop {T}s, answers at {answers_at}")
