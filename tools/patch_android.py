"""Настраивает Android-проект Winter Hub: разрешения на установку, FileProvider, свой MainActivity."""
import pathlib
import re

ROOT = pathlib.Path("android/app")
manifest = ROOT / "src/main/AndroidManifest.xml"
text = manifest.read_text(encoding="utf-8")

for p in [
    "android.permission.INTERNET",
    "android.permission.REQUEST_INSTALL_PACKAGES",
    "android.permission.REQUEST_DELETE_PACKAGES",
]:
    if p not in text:
        text = re.sub(r"(<manifest[^>]*>)", rf'\1\n    <uses-permission android:name="{p}"/>', text, count=1)

packages = ["com.dotadraft.dota_draft", "com.kbju.kbju_tracker", "com.winterhub.winter_chess", "com.winterhub.winter_mines", "com.winterhub.winter_paint", "com.winterhub.draw_school", "com.winterhub.winter_music", "com.winterhub.forest_survival", "com.winterhub.winter_chat"]
inner = "".join(f'        <package android:name="{p}"/>\n' for p in packages)
if "<queries>" in text:
    text = text.replace("<queries>", "<queries>\n" + inner.rstrip("\n"), 1)
else:
    text = text.replace("</manifest>", "    <queries>\n" + inner + "    </queries>\n</manifest>")

provider = (
    '        <provider android:name="androidx.core.content.FileProvider"\n'
    '            android:authorities="${applicationId}.fileprovider"\n'
    '            android:exported="false" android:grantUriPermissions="true">\n'
    '            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/hub_paths"/>\n'
    "        </provider>\n"
)
if "fileprovider" not in text:
    text = text.replace("</application>", provider + "    </application>", 1)
text = re.sub(r'android:label="[^"]*"', 'android:label="Winter Hub"', text, count=1)
manifest.write_text(text, encoding="utf-8")

xml = ROOT / "src/main/res/xml"
xml.mkdir(parents=True, exist_ok=True)
(xml / "hub_paths.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<paths>\n    <cache-path name="apk" path="."/>\n    <files-path name="files" path="."/>\n</paths>\n',
    encoding="utf-8",
)

# MainActivity с каналом для установки, запуска и удаления приложений.
kt_dir = ROOT / "src/main/kotlin/com/winterhub/winter_hub"
kt_dir.mkdir(parents=True, exist_ok=True)
for old in ROOT.glob("src/main/kotlin/**/MainActivity.kt"):
    old.unlink()
(kt_dir / "MainActivity.kt").write_text('''package com.winterhub.winter_hub

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "winterhub/apps").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "version" -> {
                        val pkg = call.argument<String>("pkg")!!
                        try {
                            val info = packageManager.getPackageInfo(pkg, 0)
                            val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode.toInt() else @Suppress("DEPRECATION") info.versionCode
                            result.success(code)
                        } catch (e: Exception) {
                            result.success(-1)
                        }
                    }
                    "launch" -> {
                        val i = packageManager.getLaunchIntentForPackage(call.argument<String>("pkg")!!)
                        if (i == null) result.success(false) else {
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success(true)
                        }
                    }
                    "uninstall" -> {
                        val i = Intent(Intent.ACTION_DELETE, Uri.parse("package:" + call.argument<String>("pkg")!!))
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    }
                    "canInstall" -> result.success(if (Build.VERSION.SDK_INT >= 26) packageManager.canRequestPackageInstalls() else true)
                    "installSettings" -> {
                        if (Build.VERSION.SDK_INT >= 26) {
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + packageName)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        }
                        result.success(true)
                    }
                    "install" -> {
                        val f = File(call.argument<String>("path")!!)
                        val uri = FileProvider.getUriForFile(this, packageName + ".fileprovider", f)
                        val i = Intent(Intent.ACTION_VIEW)
                        i.setDataAndType(uri, "application/vnd.android.package-archive")
                        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("error", e.message, null)
            }
        }
    }
}
''', encoding="utf-8")

gradle = ROOT / "build.gradle.kts"
g = gradle.read_text(encoding="utf-8")
if "androidx.core:core" not in g:
    if re.search(r"^dependencies\s*\{", g, re.M):
        g = re.sub(r"^dependencies\s*\{", 'dependencies {\n    implementation("androidx.core:core-ktx:1.13.1")', g, count=1, flags=re.M)
    else:
        g += '\ndependencies {\n    implementation("androidx.core:core-ktx:1.13.1")\n}\n'
gradle.write_text(g, encoding="utf-8")
print("patched")
