---
name: bing-images-cdp-workaround
description: Use Bing Images instead of Google Images when scraping images via CDP/Playwright — Google captchas CDP browsers
category: browser-automation
---

# Bing Images CDP Workaround

## Problem
Google Images captcha-blocks CDP/Playwright browser traffic. All image search attempts from automated browsers return captcha pages.

## Solution
Use **Bing Images** instead. Bing exposes image URLs directly in DOM links via `mediaurl` parameter.

## URL Format
```
https://www.bing.com/images/search?q={topic}&first=1&cw=1280&ch=720
```

Result links contain: `mediaurl=https%3A%2F%2Fexample.com%2Fimage.jpg`

## Code Pattern (Python + Playwright CDP)

```python
import urllib.parse, httpx, asyncio, time, random

async def search_bing_images(ctx, topic: str) -> str:
    search_q = urllib.parse.quote(topic[:50])
    b_page = await ctx.new_page()
    
    await b_page.goto(
        f"https://www.bing.com/images/search?q={search_q}&first=1&cw=1280&ch=720",
        wait_until="domcontentloaded", timeout=30000
    )
    await asyncio.sleep(3)
    
    # Extract media URLs from DOM link hrefs
    media_urls = await b_page.evaluate("""() => {
        const links = Array.from(document.querySelectorAll('a[href*="mediaurl"]'));
        const urls = [];
        for (const link of links) {
            try {
                const params = new URLSearchParams(link.href.split('?')[1] || '');
                const mediaUrl = params.get('mediaurl');
                if (mediaUrl && mediaUrl.startsWith('http')) {
                    urls.push(decodeURIComponent(mediaUrl));
                }
            } catch(e) {}
            if (urls.length >= 8) break;
        }
        return urls;
    }""")
    
    # Download first valid image
    for img_url in media_urls:
        try:
            async with b_page.context.request.get(img_url, timeout=15) as resp:
                if resp.status == 200:
                    img_bytes = await resp.body()
                    if len(img_bytes) > 5000:
                        ext = "jpg"
                        ct = resp.headers.get("content-type", "")
                        if "webp" in ct.lower(): ext = "webp"
                        elif "png" in ct.lower(): ext = "png"
                        out_path = f"/tmp/img_{int(time.time())}_{random.randint(100,999)}.{ext}"
                        with open(out_path, "wb") as f:
                            f.write(img_bytes)
                        return out_path
        except:
            continue
    return None
```

## Files
- `~/.kimaki/projects/ai-cdp-browser/scripts/social_workflow_3source.py`
- `~/.kimaki/projects/ai-cdp-browser/scripts/social_workflow.py`

## Pitfalls
- Use Bing `/images/search` NOT Google `tbm=isch`
- Some `mediaurl` values return 404 (CDN expired) — skip and try next
- URL-decode `mediaurl` before downloading
- Check `resp.status == 200` before saving
