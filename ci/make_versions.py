"""Собирает versions.json: свежие сборки всех приложений из catalog.json.

Хаб скачивает один этот файл вместо запросов к GitHub API
(без ключа GitHub разрешает только 60 запросов в час).
Формат записи совпадает с Release.toJson() в lib/catalog.dart:
  b — номер сборки, d — дата, a — файлы (имя → ссылка), s — размеры, h — SHA-256 файлов.

Запуск: python3 ci/make_versions.py [куда_записать] [прошлая_сводка]
Если про какое-то приложение GitHub не ответил, его записи берутся из прошлой сводки
(раньше они просто пропадали, и хаб писал «Скоро будет для этой системы»).
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


def digest_hex(d):
    d = (d or "").strip().lower()
    if not d.startswith("sha256:"):
        return ""
    h = d[7:]
    return h if re.fullmatch(r"[0-9a-f]{64}", h) else ""


def pick(rels, asset):
    for rel in rels:
        if rel.get("draft") or rel.get("prerelease"):
            continue
        files = rel.get("assets", [])
        assets = {a["name"]: a["browser_download_url"] for a in files}
        if asset not in assets:
            continue
        sizes = {a["name"]: a.get("size", 0) for a in files}
        hashes = {a["name"]: digest_hex(a.get("digest")) for a in files}
        m = re.search(r"(\d+)$", rel.get("tag_name", ""))
        return {"b": int(m.group(1)) if m else 0, "d": (rel.get("published_at") or "").split("T")[0],
                "a": assets, "s": sizes, "h": {k: v for k, v in hashes.items() if v}}
    return None


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f).get("releases", {})
    except Exception:  # noqa: BLE001
        return {}


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else "versions.json"
    prev = load(sys.argv[2] if len(sys.argv) > 2 else out_path)
    catalog = json.load(open("catalog.json", encoding="utf-8"))
    out, errors = {}, 0
    for app in catalog.get("apps", []) + [HUB]:
        repo = app["repo"]
        keys = [f"{repo}|{(app.get(side) or {}).get('asset')}" for side in ("android", "windows")
                if (app.get(side) or {}).get("asset")]
        try:
            rels = releases(repo)
        except Exception as e:  # noqa: BLE001
            print(f"::warning::{repo}: {e} — оставляю прошлые данные")
            errors += 1
            for k in keys:
                if k in prev:
                    out[k] = prev[k]
            continue
        for side in ("android", "windows"):
            asset = (app.get(side) or {}).get("asset")
            if asset:
                r = pick(rels, asset)
                if r:
                    out[f"{repo}|{asset}"] = r
    if errors and not out:
        sys.exit(1)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "releases": out},
                  f, ensure_ascii=False, indent=1, sort_keys=True)
    print("versions.json:", len(out), "файлов, ошибок:", errors)


if __name__ == "__main__":
    main()
