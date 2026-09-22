#!/usr/bin/env bash
# =====================================================================
#  MobiX IDE — сборка APK из Termux БЕЗ Gradle
#  Пакет: com.mobix.ide.android     Минимальный Android: 8.0 (API 26)
# ---------------------------------------------------------------------
#  Пайплайн (ровно то, что делает Gradle внутри, но вручную):
#     res/  --aapt2 compile-->  res.zip
#           --aapt2 link--->   APK с ресурсами + сгенерированный R.java
#     *.java --javac/ecj-->     *.class --d8--> classes.dex
#     APK + classes.dex --zip--> --apksigner--> готовый APK
#
#  Запуск:      bash build.sh
#  Установка:   bash install.sh        (или см. вывод в конце)
#  Переменные, которые можно переопределить:
#     MOBIX_MIN_SDK=26  MOBIX_TARGET_SDK=34  MOBIX_APK_NAME=... 
#     MOBIX_KEYSTORE=/path/debug.keystore  MOBIX_NO_DOWNLOAD=1
# =====================================================================
set -euo pipefail

# ---------- 0. Пути -------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------- 1. Настройки --------------------------------------------
PACKAGE="${MOBIX_PACKAGE:-com.mobix.ide.android}"
API_MIN="${MOBIX_MIN_SDK:-26}"                       # Android 8.0
API_TARGET="${MOBIX_TARGET_SDK:-34}"                 # Android 14
APK_NAME="${MOBIX_APK_NAME:-MobiX-IDE-debug.apk}"

BUILD="$SCRIPT_DIR/build"
DIR_GEN="$BUILD/gen"            # сгенерированный R.java
DIR_CLASSES="$BUILD/classes"    # .class файлы
DIR_DEX="$BUILD/dex"            # classes.dex
RES_ZIP="$BUILD/resources.zip"
UNSIGNED="$BUILD/app-unsigned.apk"

KEYSTORE="${MOBIX_KEYSTORE:-$HOME/.android/debug.keystore}"
KEY_ALIAS="${MOBIX_KEY_ALIAS:-androiddebugkey}"
STORE_PASS="${MOBIX_STOREPASS:-android}"
KEY_PASS="${MOBIX_KEYPASS:-android}"

ANDROID_JAR="${ANDROID_JAR:-}"
PLATFORM_URL="${MOBIX_PLATFORM_URL:-https://dl.google.com/android/repository/platform-33_r02.zip}"
PLATFORM_DIR_IN_ZIP="android-13/android.jar"   # путь android.jar внутри архива

say()  { printf '%s\n' "$*"; }
step() { printf '\n=== %s ===\n' "$*"; }
die()  { printf '\nОШИБКА: %s\n' "$*" >&2; exit 1; }

# ---------- 2. Проверка инструментов --------------------------------
step "0/6 Проверка инструментов"

have() { command -v "$1" >/dev/null 2>&1; }

# aapt2 нужен обязательно, остальное — с разумными запасными вариантами.
have aapt2     || die "нет aapt2.  Установите:  pkg install aapt2"
have apksigner || die "нет apksigner.  Установите:  pkg install apksigner"
have zip       || die "нет zip.  Установите:  pkg install zip"
have unzip     || die "нет unzip.  Установите:  pkg install unzip"

if   have d8; then DEX_TOOL="d8"
elif have dx; then DEX_TOOL="dx";  say "d8 не найден, использую dx (pkg install d8 даст более новый вариант)"
else die "нет d8 (или dx).  Установите:  pkg install d8"
fi

if   have javac; then JAVA_COMPILER="javac"
elif have ecj;   then JAVA_COMPILER="ecj";   say "javac не найден, использую ecj (pkg install ecj)"
else die "нет компилятора Java.  Установите:  pkg install openjdk-17   (или ecj)"
fi

# termux-exec/Android: пакеты Termux лежат в $PREFIX/bin, там же apksigner и т.п.
say "  aapt2     : $(command -v aapt2)"
say "  apksigner : $(command -v apksigner)"
say "  dex-тулза : $DEX_TOOL ($(command -v "$DEX_TOOL"))"
say "  компилятор: $JAVA_COMPILER ($(command -v "$JAVA_COMPILER"))"

# ---------- 3. JDK (нужен для keytool) ------------------------------
# В Termux keytool лежит в $PREFIX/opt/openjdk/bin. Если он там есть —
# сообщаем Java домашнюю папку через JAVA_HOME + -J-Duser.home, иначе
# keytool попытается писать в /data/data/com.termux/files/usr/etc/... и упадёт.
KEYTOOL_ENV=()
JDK_HOME=""
for candidate in "${PREFIX:-/data/data/com.termux/files/usr}"/opt/openjdk* ; do
    [ -x "$candidate/bin/keytool" ] && JDK_HOME="$candidate" && break
done
if [ -n "$JDK_HOME" ]; then
    KEYTOOL_ENV=(env "JAVA_HOME=$JDK_HOME" keytool "-J-Duser.home=$HOME")
elif have keytool; then
    KEYTOOL_ENV=(keytool)
else
    KEYTOOL_ENV=()
fi

# ---------- 4. android.jar (платформа Android SDK) ------------------
step "1/6 Поиск android.jar"

for candidate in \
        "$ANDROID_JAR" \
        "$HOME/.android/android.jar" \
        "$HOME/android-sdk/android.jar" \
        "${ANDROID_HOME:-}/platforms/android-$API_TARGET/android.jar" \
        "${ANDROID_HOME:-}/platforms/android-$API_MIN/android.jar" ; do
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then ANDROID_JAR="$candidate"; break; fi
done
ANDROID_JAR="${ANDROID_JAR:-}"

if [ -z "$ANDROID_JAR" ] || [ ! -f "$ANDROID_JAR" ]; then
    if [ "${MOBIX_NO_DOWNLOAD:-0}" = "1" ]; then
        die "android.jar не найден. Скачайте $PLATFORM_URL и положите java-архив как ~/.android/android.jar"
    fi
    say "android.jar не найден — скачиваю платформу Android (один раз)."
    mkdir -p "$HOME/.android"
    TMP_ZIP="$HOME/.android/$(basename "$PLATFORM_URL")"
    if   have curl; then curl -L --fail --progress-bar -o "$TMP_ZIP" "$PLATFORM_URL"
    elif have wget; then wget -O "$TMP_ZIP" "$PLATFORM_URL"
    else die "нет curl/wget, чтобы скачать android.jar.  Установите:  pkg install curl"
    fi
    # android.jar внутри zip лежит с именем каталога (например android-13/android.jar),
    # поэтому сначала пробуем известный путь, потом — поиск по маске.
    unzip -o -j "$TMP_ZIP" "$PLATFORM_DIR_IN_ZIP" -d "$HOME/.android" >/dev/null 2>&1 \
        || unzip -o -j "$TMP_ZIP" '*/android.jar' -d "$HOME/.android" >/dev/null 2>&1 \
        || unzip -o -j "$TMP_ZIP" 'android.jar' -d "$HOME/.android" >/dev/null 2>&1 \
        || die "не удалось распаковать android.jar из $TMP_ZIP"
    rm -f "$TMP_ZIP"
    ANDROID_JAR="$HOME/.android/android.jar"
fi
say "  android.jar: $ANDROID_JAR"

# ---------- 5. Версия из файла VERSION ------------------------------
VERSION_NAME="$(tr -d ' \t\r\n' < "$SCRIPT_DIR/VERSION" 2>/dev/null || true)"
[ -n "$VERSION_NAME" ] || VERSION_NAME="1.0.0"

# versionCode = major*10000 + minor*100 + patch  (1.2.3 -> 10203).
# Разбираем строку только средствами bash — awk в Termux может отсутствовать.
VER_MAJOR="${VERSION_NAME%%.*}"
VER_REST="${VERSION_NAME#*.}"
if [ "$VER_REST" = "$VERSION_NAME" ]; then
    VER_MINOR=0; VER_PATCH=0
else
    VER_MINOR="${VER_REST%%.*}"
    VER_PATCH="${VER_REST#*.}"
    [ "$VER_PATCH" = "$VER_REST" ] && VER_PATCH=0
fi
VER_MAJOR="${VER_MAJOR//[!0-9]/}"; VER_MINOR="${VER_MINOR//[!0-9]/}"; VER_PATCH="${VER_PATCH//[!0-9]/}"
VER_MAJOR="${VER_MAJOR:-0}"; VER_MINOR="${VER_MINOR:-0}"; VER_PATCH="${VER_PATCH:-0}"
VERSION_CODE=$(( 10#$VER_MAJOR * 10000 + 10#$VER_MINOR * 100 + 10#$VER_PATCH ))
[ "$VERSION_CODE" -ge 1 ] || VERSION_CODE=1

say ""
say "MobiX IDE v$VERSION_NAME (код $VERSION_CODE)  →  $APK_NAME"
say "minSdk=$API_MIN  targetSdk=$API_TARGET  пакет=$PACKAGE"

# ---------- 6. Чистка ------------------------------------------------
step "2/6 Подготовка папки build"
rm -rf "$BUILD"
mkdir -p "$DIR_GEN" "$DIR_CLASSES" "$DIR_DEX"

# ---------- 7. Манифест с атрибутом package -------------------------
# При сборке через Gradle атрибут package="..." в манифесте ЗАПРЕЩЁН
# (AGP берёт имя пакета из namespace). При сборке без Gradle он нужен.
# Поэтому подставляем его в копию манифеста внутри build/.
# Делаем это только средствами bash (без awk/sed), попутно пропуская
# комментарии <!-- ... --> — чтобы не задеть текст внутри них.
patched=0
in_comment=0
: > "$BUILD/AndroidManifest.xml"
while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_comment" = 1 ]; then
        printf '%s\n' "$line" >> "$BUILD/AndroidManifest.xml"
        case "$line" in *'-->'*) in_comment=0 ;; esac
        continue
    fi
    case "$line" in
        *'<!--'*)
            printf '%s\n' "$line" >> "$BUILD/AndroidManifest.xml"
            case "$line" in *'-->'*) ;; *) in_comment=1 ;; esac
            continue
            ;;
    esac
    if [ "$patched" = 0 ]; then
        case "$line" in
            *'<manifest'*)
                printf '%s\n' "${line/<manifest/<manifest package=\"$PACKAGE\"}" \
                    >> "$BUILD/AndroidManifest.xml"
                patched=1
                continue
                ;;
        esac
    fi
    printf '%s\n' "$line" >> "$BUILD/AndroidManifest.xml"
done < "$SCRIPT_DIR/app/src/main/AndroidManifest.xml"

[ "$patched" = 1 ] || die "в AndroidManifest.xml нет тега <manifest>"
say "  манифест: package=\"$PACKAGE\" подставлен (только в build/)"

# ---------- 8. Ресурсы: aapt2 compile + link ------------------------
step "3/6 Компиляция ресурсов (aapt2)"
aapt2 compile --dir "$SCRIPT_DIR/app/src/main/res" -o "$RES_ZIP"

aapt2 link \
    -o "$UNSIGNED" \
    --manifest "$BUILD/AndroidManifest.xml" \
    --java "$DIR_GEN" \
    -I "$ANDROID_JAR" \
    --min-sdk-version "$API_MIN" \
    --target-sdk-version "$API_TARGET" \
    --version-code "$VERSION_CODE" \
    --version-name "$VERSION_NAME" \
    --auto-add-overlay \
    "$RES_ZIP"

# ---------- 9. Java: javac/ecj → .class -----------------------------
step "4/6 Компиляция Java-кода"
find "$SCRIPT_DIR/app/src/main/java" "$DIR_GEN" -name '*.java' > "$BUILD/sources.txt"
[ -s "$BUILD/sources.txt" ] || die "в app/src/main/java нет .java файлов"
say "  файлов на компиляцию: $(wc -l < "$BUILD/sources.txt" | tr -d ' ')"

compile_java() {
    if [ "$JAVA_COMPILER" = "javac" ]; then
        javac -encoding UTF-8 -nowarn "$@" -cp "$ANDROID_JAR" -d "$DIR_CLASSES" @"$BUILD/sources.txt"
    else
        ecj "$@" -cp "$ANDROID_JAR" -d "$DIR_CLASSES" @"$BUILD/sources.txt"
    fi
}
# Java 8-байткод максимально совместим с d8/dx на телефоне.
compile_java -source 8 -target 8 2>/dev/null \
    || { say "  повторная попытка без -source/-target"; compile_java; }

# ---------- 10. Dalvik-байткод: d8 / dx -----------------------------
step "5/6 Конвертация в classes.dex ($DEX_TOOL)"
if [ "$DEX_TOOL" = "d8" ]; then
    mapfile -t CLASSES < <(find "$DIR_CLASSES" -name '*.class')
    d8 --min-api "$API_MIN" --lib "$ANDROID_JAR" \
       --output "$DIR_DEX" "${CLASSES[@]}"
else
    dx --dex --min-sdk-version="$API_MIN" --output="$DIR_DEX/classes.dex" "$DIR_CLASSES"
fi
[ -f "$DIR_DEX/classes.dex" ] || die "classes.dex не создан"

# ---------- 11. Упаковка и подпись ----------------------------------
step "6/6 Упаковка и подпись APK"

cp "$UNSIGNED" "$BUILD/app-aligned.apk"
( cd "$DIR_DEX" && zip -q -j "$BUILD/app-aligned.apk" classes.dex )

# --- выравнивание -----------------------------------------------------
# Android 11+ (при targetSdk >= 30) требует: resources.arsc внутри APK
# лежит без сжатия и выровнен на 4 байта. Иначе установка падает:
#   "Targeting R+ (version 30 and above) requires the resources.arsc of
#    installed APKs to be stored uncompressed and aligned on a 4-byte boundary"
# Выравнивать НУЖНО до подписи, иначе подпись станет недействительной.
if have zipalign; then
    say "  zipalign -f 4 (выравнивание APK)"
    zipalign -f 4 "$BUILD/app-aligned.apk" "$BUILD/app-aligned-out.apk" \
        && mv "$BUILD/app-aligned-out.apk" "$BUILD/app-aligned.apk"
elif have python3; then
    if ! python3 "$SCRIPT_DIR/tools/apk_align.py" \
            "$BUILD/app-aligned.apk" "$BUILD/app-aligned-out.apk"; then
        die "не удалось выровнять APK (tools/apk_align.py)"
    fi
    mv "$BUILD/app-aligned-out.apk" "$BUILD/app-aligned.apk"
else
    say ""
    say "  ВНИМАНИЕ: нет ни zipalign, ни python3 — выравнивание пропущено."
    say "  Если в APK resources.arsc не выровнен, установка на Android 11+"
    say "  не пройдёт. Поставьте python и пересоберите:  pkg install python"
    say ""
fi

# Ключ разработчика: ~/.android/debug.keystore — тот же самый, что создаёт
# Android Studio, поэтому пароль/алиас стандартные (android / androiddebugkey).
if [ ! -f "$KEYSTORE" ]; then
    [ "${#KEYTOOL_ENV[@]}" -gt 0 ] || die "нет keytool, чтобы создать ключ.  Установите:  pkg install openjdk-17"
    say "  создаю ключ разработчика: $KEYSTORE"
    mkdir -p "$(dirname "$KEYSTORE")"
    "${KEYTOOL_ENV[@]}" -genkeypair \
        -keystore "$KEYSTORE" -storetype JKS -alias "$KEY_ALIAS" \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass "$STORE_PASS" -keypass "$KEY_PASS" \
        -dname "CN=Android Debug,O=Android,C=US" >/dev/null
fi

apksigner sign \
    --ks "$KEYSTORE" \
    --ks-key-alias "$KEY_ALIAS" \
    --ks-pass "pass:$STORE_PASS" \
    --key-pass "pass:$KEY_PASS" \
    --out "$SCRIPT_DIR/$APK_NAME" \
    "$BUILD/app-aligned.apk"
rm -f "$SCRIPT_DIR/$APK_NAME.idsig"

SIZE_KB=$(( $(wc -c < "$SCRIPT_DIR/$APK_NAME") / 1024 ))

# ---------- 12. Итог -------------------------------------------------
printf '\n=====================================\n'
printf ' ГОТОВО: %s (%s КБ)\n' "$APK_NAME" "$SIZE_KB"
printf '=====================================\n'

# Самопроверка подписи (не блокирует сборку, но предупреждает о проблеме).
if have apksigner && apksigner verify "$SCRIPT_DIR/$APK_NAME" >/dev/null 2>&1; then
    printf 'Подпись    : проверена (APK валиден)\n'
else
    printf 'Подпись    : проверить не удалось, посмотрите вручную:\n'
    printf '             apksigner verify --print-certs %s\n' "$APK_NAME"
fi
printf 'Детали     : aapt2 dump badging %s   (пакет, minSdk, точка входа)\n' "$APK_NAME"
printf 'Установить : bash install.sh\n'
printf 'Вручную    : cp %s ~/storage/downloads/ && termux-open ~/storage/downloads/%s\n' \
       "$APK_NAME" "$APK_NAME"
