"""Print this OpenRouter key's cumulative spend (USD) as JSON. Never prints the key.

Uses GET https://openrouter.ai/api/v1/key with OPENROUTER_API_KEY from the environment.
"""

import json
import os
import sys
import time
import urllib.request

req = urllib.request.Request(
    "https://openrouter.ai/api/v1/key",
    headers={"Authorization": f"Bearer {os.environ['OPENROUTER_API_KEY']}"},
)
with urllib.request.urlopen(req, timeout=30) as r:
    data = json.load(r).get("data", {})
keep = ["usage", "usage_daily", "usage_weekly", "limit", "limit_remaining"]
json.dump({"time_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **{k: data.get(k) for k in keep}}, sys.stdout)
print()
