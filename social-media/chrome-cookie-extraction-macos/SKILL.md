---
name: chrome-cookie-extraction-macos
description: Chrome CDP cookie extraction on macOS — what fails (Chrome for Testing pipe mode, encrypted SQLite, Keychain lock) and what works (Facebook OAuth Device Login)
triggers:
  - chrome cookies extraction macos
  - facebook cdp cookies headless
  - chrome-remote-interface python macos
  - social-mcp chrome session
tags:
  - chrome
  - macos
  - cookies
  - cdp
  - facebook
  - oauth
  - dead-ends
---

# Chrome Cookie Extraction on macOS — Dead Ends & Working Path

## Context

When trying to read Facebook/Instagram cookies from Chrome on macOS to use with Graph API:
- Goal: Extract `c_user`, `xs` etc. from Chrome's cookie store without requiring Facebook OAuth
- Use case: social-mcp, any MCP that needs to impersonate a logged-in Chrome session

---

## What Does NOT Work

### 1. Chrome for Testing + CDP TCP (FAILS)
- AIpuss-browser and similar tools use **Chrome for Testing** (`~/.agent-browser/browsers/chrome-*/...`)
- It runs with `--remote-debugging-pipe` (pipe mode), **not** TCP port
- External CDP clients cannot connect via WebSocket TCP when pipe mode is active
- **Finding**: `ps aux | grep Chrome` shows `chrome_cr` processes using temp `user-data-dir=/var/folders/...`

### 2. CDP JSON API polling for tabs (FAILS when pipe mode)
- The `/json/version` HTTP endpoint is unavailable when Chrome uses pipe mode
- Even if you find the real CDP port, Chrome blocks connections from non-Chrome clients on macOS

### 3. Reading ~/Library/.../Profile N/Cookies directly (FAILS)
- Chrome cookies in `~/Library/Application Support/Google/Chrome/Profile N/Cookies` are **encrypted at rest**
- On macOS, Chrome uses `Chrome Safe Storage` in the macOS Keychain (AES-256-GCM)
- `security find-generic-password -s "Chrome Safe Storage" -w` **times out** because Keychain is locked
- Requires user interaction/unlock, cannot be automated headlessly

### 4. Starting Chrome with same user-data-dir as running Chrome (FAILS)
- Running Chrome (including Chrome for Testing) creates `Singleton*` lock files in the profile dir
- A second Chrome instance using the same `--user-data-dir` will either redirect to the running instance or fail to start
- Even if Chrome is killed, the profile may be in an inconsistent state

### 5. Copying profile to new location and starting Chrome there
- Profile 3 may not contain Facebook cookies if the user never logged into Facebook via the system Chrome.app
- Facebook cookies were found to be **empty** in ~/Library Profile 3 in the actual case

---

## What DOES Work

### Facebook OAuth Device Login (WORKING)

Facebook officially supports a Device Login flow for headless apps — no browser cookies needed.

**Flow:**
1. POST to `https://graph.facebook.com/v19.0/device/login_status` with `client_id=facebook_desktop`
2. Get `{device_code, user_code, verification_uri}`
3. User visits `https://facebook.com/device` in any browser, enters `user_code`, logs in
4. Poll `https://graph.facebook.com/v19.0/device/login_status` with `device_code` until `access_token` is returned
5. Save `access_token` to `~/.social_mcp_token.json`

**Scopes needed:**
```
pages_manage_posts,pages_read_user_contacts,instagram_basic,
instagram_content_publish,threads_content_publish
```

**Advantages:**
- Official, supported by Facebook
- Token can be cached to disk and reused
- No cookies, no Keychain, no Chrome dependency
- Works headlessly

**Disadvantages:**
- Requires one-time user interaction to authorize
- Token may expire and need re-authentication
- Need a Facebook App (or use `facebook_desktop` client_id with limited scope)

---

## Diagnostic Commands

```bash
# Check what Chrome processes are running and their debug mode
ps aux | grep "Chrome" | grep -v grep

# Check if Chrome is using pipe (remote-debugging-pipe) vs TCP port
ps aux | grep "Chrome" | grep "user-data-dir" | grep -v grep

# Find actual CDP port for a running Chrome
lsof -Pan -p <PID> -i TCP | grep LISTEN

# Check if ~/Library Profile 3 has Facebook cookies
python3 -c "
import sqlite3, os
conn = sqlite3.connect(os.path.expanduser('~/Library/Application Support/Google/Chrome/Profile 3/Cookies'))
c = conn.cursor()
c.execute(\"SELECT name, host_key FROM cookies WHERE host_key LIKE '%facebook%' OR host_key LIKE '%instagram%'\")
print(c.fetchall())
conn.close()
"

# Check Chrome Safe Storage Keychain
security find-generic-password -s \"Chrome Safe Storage\" 2>&1 | head -5
```

---

## Key Files

- Chrome cookies (encrypted): `~/Library/Application Support/Google/Chrome/Profile N/Cookies`
- Chrome for Testing binary: `~/.agent-browser/browsers/chrome-*/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing`
- Keychain: `~/Library/Keychains/login.keychain-db`
