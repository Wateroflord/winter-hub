"""Собирает versions.json: свежие сборки всех приложений из catalog.json.

Хаб скачивает один этот файл вместо 13 запросов к GitHub API
(без ключа GitHub разрешает только 60 запросов в час).
Формат записи совпадает с Release.toJson() в lib/catalog.dart.
"""
import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone

HUB = {"repo": "Wateroflord/winter-hub", "android": {"asset": "Winter-Hub.apk"}, "windows": {"asset": "Winter-Hub-Setup.exe"}}
token = os.environ.get("GH_TOKEN", "")


def releases(repo):
    req = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases?per_page=10",
                                 headers={"Accept": "application/vnd.github+json", "User-Agent": "winter-hub-versions",
                                          **({"Authorization": f"Bearer {token}"} if token else {})})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def pick(rels, asset):
    for rel in rels:
        if rel.get("draft") or rel.get("prerelease"):
            continue
        assets = {a["name"]: a["browser_download_url"] for a in rel.get("assets", [])}
        sizes = {a["name"]: a.get("size", 0) for a in rel.get("assets", [])}
        if asset not in assets:
            continue
        m = re.search(r"(\d+)$", rel.get("tag_name", ""))
        return {"b": int(m.group(1)) if m else 0, "d": (rel.get("published_at") or "").split("T")[0], "a": assets, "s": sizes}
    return None


def main():
    catalog = json.load(open("catalog.json", encoding="utf-8"))
    out, errors = {}, 0
    for app in catalog.get("apps", []) + [HUB]:
        repo = app["repo"]
        try:
            rels = releases(repo)
        except Exception as e:  # noqa: BLE001
            print(f"::warning::{repo}: {e}")
            errors += 1
            continue
        for side in ("android", "windows"):
            asset = (app.get(side) or {}).get("asset")
            if asset:
                r = pick(rels, asset)
                if r:
                    out[f"{repo}|{asset}"] = r
    if errors and not out:
        sys.exit(1)
    old, old_time = {}, None
    try:
        prev = json.load(open("versions.json", encoding="utf-8"))
        old = prev.get("releases", {})
        old_time = datetime.strptime(prev.get("updated", ""), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except Exception:  # noqa: BLE001
        pass
    # Без изменений файл всё равно обновляется раз в 6 часов: по полю updated хаб
    # понимает, что сводка живая (если GitHub перестанет её обновлять — хаб спросит API сам).
    if old == out and old_time and (datetime.now(timezone.utc) - old_time).total_seconds() < 6 * 3600:
        print("Без изменений")
        return
    json.dump({"updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "releases": out},
              open("versions.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
    print("versions.json обновлён:", len(out), "файлов")


if __name__ == "__main__":
    main()
