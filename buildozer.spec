[app]
title = Lycoris-control
package.name = controlentradas
package.domain = org.reidchend
source.dir = .
source.include_exts = py,png,jpg,kv,atlas,db
version = 0.1
requirements = python3,kivy

# (AQUÍ) Si usas KivyMD, cámbialo a:
# requirements = python3,kivy,kivymd,pillow

orientation = portrait
fullscreen = 0
android.archs = armeabi-v7a, arm64-v8a
android.allow_backup = True

[buildozer]
log_level = 2
warn_on_root = 1