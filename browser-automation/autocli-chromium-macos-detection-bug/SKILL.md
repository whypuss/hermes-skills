---
name: autocli-chromium-macos-detection-bug
description: autocli (nashsu/AutoCLI) reports "Chrome is not running" on macOS when Chromium is running — root cause is hardcoded process name check
tags:
  - autocli
  - browser-automation
  - macos
  - chromium
  - debug
created: 2026-04-25
---

# autocli Chromium macOS Detection Bug

## Problem
autocli reports "Chrome is not running" on macOS even when Chromium with the OpenCLI extension is actively running on port 9333.

## Root Cause
File: `crates/autocli-browser/src/bridge.rs`

```rust
fn is_chrome_running() -> bool {
    if cfg!(target_os = "macos") {
        std::process::Command::new("pgrep")
            .args(["-x", "Google Chrome"])  // ← BUG: hardcoded name
            // ...
    }
}
```

The function hardcodes `"Google Chrome"` but the process name on macOS for Chromium is `"Chromium"`. `pgrep -x "Google Chrome"` returns empty even when Chromium is running.

## Fix
Modify the macOS branch to also check for "Chromium", then recompile from source.

## Workarounds
1. Use Google Chrome instead of Chromium
2. Wait for autocli upstream fix

## Verification
```bash
# Returns process info if Chromium is running
pgrep -x "Chromium"
# Returns empty (the bug)
pgrep -x "Google Chrome"
```
