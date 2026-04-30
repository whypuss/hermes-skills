---
name: script-parser-inline-tags
description: Fix script_parser.py for inline multi-speaker tag parsing (Cantonese support)
category: debugging
---

# script_parser Inline Tags Fix — Podcast Gen

## Context
Fixed `script_parser.py` for podcast-gen backend. Parser only matched `[tag]` at line start, couldn't handle inline multi-speaker format needed for Cantonese scripts like `[男] text [女] text`.

## Root Cause
1. Original `re.match(pattern, line)` only matched `[tag]` at line start
2. Cantonese contains "我係" where "係" has "男" → partial match incorrectly triggered
3. No support for same-line alternating `[男]`/`[女]` tags

## Solution
Use `re.finditer()` with positional slicing — works for both:
- Multi-line format (one tag per line)
- Inline format (multiple tags same line)

```python
tag_pattern = re.compile(r'\[([^\]:]+)(?::([^\]]+))?\]', re.IGNORECASE)

for line in lines:
    line = line.strip()
    matches = list(tag_pattern.finditer(line))
    if not matches:
        # no tag in line → append to previous segment
        if raw_segments:
            tag_v, voice, text = raw_segments[-1]
            raw_segments[-1] = (tag_v, voice, text + " " + line)
        continue

    for idx, m in enumerate(matches):
        tag = m.group(1).strip()
        voice = m.group(2)  # can be None
        text_start = m.end()

        # Text from tag end to next tag start (or line end)
        if idx + 1 < len(matches):
            text = line[text_start:matches[idx + 1].start()].strip()
        else:
            text = line[text_start:].strip()

        if text:
            raw_segments.append((tag, voice, text))
```

## Key Pitfalls

### `re.split` doesn't work for trailing text
```python
# WRONG: re.split misses trailing text after last ]
parts = re.split(pattern, line)

# RIGHT: use finditer with positional slicing
matches = list(tag_pattern.finditer(line))
text = line[m.end():matches[idx+1].start()]
```

### `strip()` changes string content
Never do `line = line.strip()` then calculate positions on original — use stripped version consistently.

### Don't double-append text
If you append a segment for each match's text, DON'T also append "after_text" after the loop — that double-counts the last tag's trailing text.

## Files
- `/Users/whypuss/.kimaki/projects/podcast-gen/backend/script_parser.py`

## Verification
```bash
cd ~/.kimaki/projects/podcast-gen/backend
.venv-tts/bin/python -c "
from script_parser import parse_script
r = parse_script('[男] text1 [女] text2', default_male_voice='uncle_fu', default_female_voice='vivian')
print(len(r), r[0]['text'], r[1]['text'])
# Expected: 2, 'text1', 'text2'
"
```
