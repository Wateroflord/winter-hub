"""Подписывает APK приложений Winter.

Раньше Gradle на сборочном сервере каждый раз создавал НОВЫЙ случайный
debug-ключ, поэтому каждая сборка была подписана по-разному и обновление
не вставало поверх старой версии. Теперь APK подписывается одним постоянным
секретным ключом (секрет WINTER_SIGNING).

Если секрет не задан, APK подписывается старым публичным ключом
(legacy/shared-old.keystore) — подпись хотя бы постоянная, но в сборке
появляется предупреждение. Когда секрет добавят, новый ключ подписывается
«со сменой ключа» (APK Signature Scheme v3, key rotation): версии со старым
ключом обновятся без удаления, а APK только со старым публичным ключом
поверх уже не установится.

Запуск: python3 sign_apk.py <apk> [shared]
"""
import base64
import glob
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OLD_ALIAS, OLD_PASS = "androiddebugkey", "android"


def apksigner():
    home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or "/usr/local/lib/android/sdk"
    found = glob.glob(os.path.join(home, "build-tools", "*", "apksigner"))
    if not found:
        print("::error title=sign::apksigner не найден в Android SDK")
        sys.exit(1)

    def ver(p):
        v = os.path.basename(os.path.dirname(p)).split("-")[0]
        return [int(x) if x.isdigit() else 0 for x in v.split(".")]

    return sorted(found, key=ver)[-1]


def run(cmd, env):
    shown = " ".join(cmd)
    print("$", shown)
    r = subprocess.run(cmd, env=env, capture_output=True, text=True)
    out = (r.stdout or "") + (r.stderr or "")
    print(out)
    if r.returncode != 0:
        print(f"::error title=sign::{cmd[1]} завершился с ошибкой: {out.strip().splitlines()[-1] if out.strip() else r.returncode}")
        sys.exit(1)
    return out


def main():
    apk = sys.argv[1]
    legacy = sys.argv[2] if len(sys.argv) > 2 else "shared"
    old_ks = os.path.join(HERE, "legacy", f"{legacy}-old.keystore")
    if not os.path.exists(old_ks):
        print(f"::error title=sign::нет старого ключа {legacy}")
        sys.exit(1)
    tool = apksigner()
    env = dict(os.environ, OLD_PASS=OLD_PASS)
    tmp = tempfile.mkdtemp()
    out_apk = os.path.join(tmp, "signed.apk")
    old = ["--ks", old_ks, "--ks-key-alias", OLD_ALIAS, "--ks-pass", "env:OLD_PASS", "--key-pass", "env:OLD_PASS"]

    blob = os.environ.get("WINTER_SIGNING", "").strip()
    if not blob:
        print("::warning title=Подпись::Секрет WINTER_SIGNING не задан — APK подписан старым публичным ключом. "
              "Добавь секрет в Settings → Secrets and variables → Actions.")
        run([tool, "sign", *old, "--v4-signing-enabled", "false", "--out", out_apk, apk], env)
    else:
        try:
            data = json.loads(base64.b64decode(blob))
        except Exception:
            print("::error title=Подпись::Секрет WINTER_SIGNING повреждён — вставь его заново целиком")
            sys.exit(1)
        new_ks = os.path.join(tmp, "new.p12")
        with open(new_ks, "wb") as f:
            f.write(base64.b64decode(data["keystore"]))
        env["NEW_PASS"] = data["password"]
        new = ["--ks", new_ks, "--ks-key-alias", data.get("alias", "winter"),
               "--ks-pass", "env:NEW_PASS", "--key-pass", "env:NEW_PASS"]
        lineage = os.path.join(tmp, "lineage.bin")
        run([tool, "rotate", "--out", lineage, "--old-signer", *old, "--new-signer", *new], env)
        run([tool, "sign", *old, "--next-signer", *new, "--lineage", lineage,
             "--rotation-min-sdk-version", "28", "--v4-signing-enabled", "false",
             "--out", out_apk, apk], env)
        os.remove(new_ks)

    run([tool, "verify", "--verbose", "--print-certs", out_apk], env)
    os.replace(out_apk, apk)
    print("APK подписан:", apk)


if __name__ == "__main__":
    main()
