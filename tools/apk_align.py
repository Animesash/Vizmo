#!/usr/bin/env python3
"""
apk_align.py — выравнивает APK так, как это делает `zipalign -f 4`.

Зачем: начиная с Android 11 (если targetSdk >= 30) система требует, чтобы
файл resources.arsc внутри APK лежал БЕЗ сжатия и был выровнен на 4 байта.
Иначе установка падает с ошибкой:

    Targeting R+ (version 30 and above) requires the resources.arsc of
    installed APKs to be stored uncompressed and aligned on a 4-byte boundary

В Termux пакета `zipalign` нет, поэтому выравнивание делает этот скрипт.
Нужен только стандартный Python 3 (`pkg install python`) — сторонних
библиотек нет. Выравнивание делается добавлением «дополнительного поля»
(extra field с ID 0xD935 — как в AOSP zipalign) в локальную шапку записи,
поэтому сами файлы внутри APK не меняются.

Использование:
    python3 tools/apk_align.py вход.apk выход.apk

Код возврата: 0 — готово и проверено, 1 — выровнять не удалось.
"""

import struct
import sys
import zipfile

ALIGN = 4                     # требование Android: 4 байта
ARSC = "resources.arsc"       # имя файла, который обязан быть выровнен
EXTRA_ID = 0xD935             # ID extra-поля, который использует AOSP zipalign
LOCAL_HEADER = 30             # фиксированный размер локальной шапки zip


def _padding_for(pos: int, name_len: int) -> int:
    """Сколько байт extra-поля нужно, чтобы данные легли на границу 4 байт."""
    base = pos + LOCAL_HEADER + name_len
    pad = (-base) % ALIGN
    if 0 < pad < 4:           # extra-поле короче 4 байт невозможно (заголовок 4 байта)
        pad += ALIGN
    return pad


def align(src: str, dst: str) -> bool:
    ok = True
    with zipfile.ZipFile(src, "r") as zin, zipfile.ZipFile(dst, "w") as zout:
        for info in zin.infolist():
            data = zin.read(info.filename)
            name = info.filename

            zi = zipfile.ZipInfo(name, date_time=info.date_time)
            zi.external_attr = info.external_attr
            zi.create_system = info.create_system
            zi.internal_attr = info.internal_attr

            # resources.arsc всегда без сжатия, остальное — как было
            if name == ARSC:
                zi.compress_type = zipfile.ZIP_STORED
            else:
                zi.compress_type = info.compress_type

            zi.extra = b""
            if name == ARSC:
                pad = _padding_for(zout.fp.tell(), len(name.encode("utf-8")))
                if pad:
                    zi.extra = struct.pack("<HH", EXTRA_ID, pad - 4) + b"\x00" * (pad - 4)

            zout.writestr(zi, data)

    # ---- проверка результата -------------------------------------------
    with zipfile.ZipFile(dst, "r") as z:
        for info in z.infolist():
            offset = info.header_offset + LOCAL_HEADER + len(info.filename) + len(info.extra)
            if info.filename == ARSC:
                stored = info.compress_type == zipfile.ZIP_STORED
                aligned = offset % ALIGN == 0
                print("  resources.arsc: %s, выравнивание 4 байта: %s (offset %d)"
                      % ("без сжатия" if stored else "СЖАТ — ошибка", "да" if aligned else "НЕТ", offset))
                ok = stored and aligned
    return ok


def main(argv) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    src, dst = argv[1], argv[2]
    print("  выравнивание APK: %s -> %s" % (src, dst))
    if not align(src, dst):
        print("  ОШИБКА: resources.arsc не удалось выровнять", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
