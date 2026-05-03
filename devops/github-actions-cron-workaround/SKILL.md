---
name: github-actions-cron-workaround
description: GitHub Actions cron/schedule never triggers — use cron-job.org instead
category: devops
---

# GitHub Actions Cron Not Triggering — Workaround

## Problem

GitHub Actions workflows with `schedule` cron triggers never fire. API returns:
```
"Workflow does not have 'workflow_dispatch' trigger" (HTTP 422)
```
Even though the YAML clearly has `workflow_dispatch` and `schedule` declared.

Affected: specific workflows (e.g. `cfnew-hc.yml`). Other workflows in the same repo (e.g. `test.yml`) work fine. This is a GitHub Actions bug where the trigger system doesn't correctly register certain workflows.

## Symptoms

- `workflow_dispatch` API works for some workflows but not others (same repo, same PAT, same permissions)
- `schedule` cron events never trigger (0 "schedule" runs even after 20+ minutes)
- Pushing new commits / deleting and recreating workflow files does NOT fix it
- `gh workflow run` returns the same 422 error
- Cron jobs don't appear in GitHub Actions → Cron page

## Workaround: External Cron Service

Use cron-job.org (free) as a replacement:

1. Create account at https://cron-job.org
2. Create a cron job:
   - URL: your health check endpoint (e.g. `https://your-worker.workers.dev/health`)
   - Schedule: `*/5` minutes (or desired interval)
   - Request method: `GET`
3. This keeps the service warm and triggers health checks externally

## If You Still Need GitHub Actions for Secrets/Deploy

When the workflow eventually works, the recommended health-check + auto-redeploy pattern:

```yaml
name: Health Check
on:
  schedule:
    - cron: "*/5 * * * *"
  workflow_dispatch:

jobs:
  monitor:
    runs-on: ubuntu-latest
    steps:
      - name: Check health
        id: health
        run: |
          HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://your.workers.dev/)
          echo "http_code=$HTTP_CODE" >> $GITHUB_OUTPUT
          echo "dead=$([ "$HTTP_CODE" = "200" ] && echo "false" || echo "true")" >> $GITHUB_OUTPUT

      - name: Redeploy if dead
        if: steps.health.outputs.dead == 'true'
        run: |
          # Redeploy logic here
```

## Debug Commands

```bash
# Check all workflow runs and their event types
gh api repos/OWNER/REPO/actions/runs | python3 -c "
import sys,json; d=json.load(sys.stdin)
from collections import Counter
c = Counter(r['event'] for r in d['workflow_runs'])
print(dict(c))"

# Check workflow IDs
gh api repos/OWNER/REPO/actions/workflows | python3 -c "
import sys,json; d=json.load(sys.stdin)
for w in d.get('workflows',[]): print(w['id'], w['name'], w['path'])"
```

## Related

- cron-job.org free cron: https://cron-job.org
- GitHub Actions schedule docs: https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule
