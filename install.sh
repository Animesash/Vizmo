#!/usr/bin/env bash
# =====================================================================
#  MobiX IDE — установка собранного APK прямо с телефона
#  (Android 8+ требует разрешить установку из неизвестных источников,
#   но когда APK открыт через termux-open — система сама спросит.)
#  Запуск:  bash install.sh
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
APK_NAME="${MOBIX_APK_NAME:-MobiX-IDE-debug.apk}"
APK="$SCRIPT_DIR/$APK_NAME"

[ -f "$APK" ] || { echo "Нет файла $APK — сначала соберите: bash build.sh"; exit 1; }

# Куда кладём: сначала общая папка Downloads, иначе — домашняя папка Termux.
DEST_DIR="$HOME/storage/downloads"
[ -d "$DEST_DIR" ] || DEST_DIR="$HOME/storage/shared/Download"
if [ ! -d "$DEST_DIR" ]; then
    echo "Нет доступа к папке загрузок. Один раз выполните в Termux: termux-setup-storage"
    DEST_DIR="$HOME"
fi

cp -f "$APK" "$DEST_DIR/"
echo "APK скопирован: $DEST_DIR/$APK_NAME"

if command -v termux-open >/dev/null 2>&1 && [ "$DEST_DIR" != "$HOME" ]; then
    # Открываем системный установщик пакетов.
    termux-open "$DEST_DIR/$APK_NAME" || true
else
    echo "Откройте файл вручную и разрешите установку:"
    echo "  $DEST_DIR/$APK_NAME"
fi
