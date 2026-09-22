# MobiX IDE

Минимальное Android-приложение (скелет любого проекта) для сборки **на смартфоне в Termux** —
без Android Studio, без компьютера и без Gradle.

| | |
|---|---|
| **Название** | MobiX IDE |
| **Пакет (applicationId)** | `com.mobix.ide.android` |
| **Минимальный Android** | **8.0 (Oreo, API 26)** |
| **targetSdk** | 34 (Android 14) |
| **Главный экран** | полностью чёрный, без панели действий |
| **Язык** | Java (только стандартный Android framework, без AndroidX) |
| **Зависимости** | их нет — значит проект собирается быстро и на телефоне |

Проверено на реальной сборке: APK собирается, подписывается, `resources.arsc` выровнен,
`aapt2 dump badging` показывает `package: com.mobix.ide.android`, `sdkVersion: 26`,
`targetSdkVersion: 34`, `launchable-activity: MainActivity`.

---

## 1. Что внутри

```
MobiX/
├── build.sh                        ← сборка APK в Termux БЕЗ Gradle (главный файл)
├── install.sh                      ← перенести APK в «Загрузки» и открыть установщик
├── VERSION                         ← версия приложения (1.0.0)
├── settings.gradle                 ← для варианта сборки через Gradle
├── build.gradle                    ← версия Android Gradle Plugin
├── gradle.properties               ← настройки памяти Gradle (для слабых телефонов)
├── local.properties.example        ← подсказка, где искать Android SDK
├── tools/
│   └── apk_align.py                ← выравнивание APK (аналог zipalign, нужен для Android 11+)
└── app/
    ├── build.gradle                ← имя пакета, minSdk 26, targetSdk 34
    ├── proguard-rules.pro
    └── src/main/
        ├── AndroidManifest.xml     ← главный экран, чёрная тема, иконка
        ├── java/com/mobix/ide/android/
        │   └── MainActivity.java   ← «мозг» приложения: чёрный экран + каркас для IDE
        └── res/
            ├── layout/activity_main.xml      ← чёрный экран во весь размер
            ├── values/strings.xml            ← название «MobiX IDE»
            ├── values/colors.xml             ← чёрный / белый
            ├── values/themes.xml             ← Theme.MobiX (чёрная, без ActionBar)
            ├── drawable/ic_launcher_*.xml    ← иконка (белая «M» на чёрном)
            ├── mipmap-anydpi-v26/            ← адаптивная иконка (Android 8+)
            └── xml/backup_rules.xml
```

---

## 2. Сборка в Termux (вариант без Gradle) — быстрый путь

Установите Termux **из F-Droid** (версия из Google Play давно заброшена), откройте его и выполните:

```bash
# 1. Обновление и все нужные инструменты
pkg update -y && pkg upgrade -y
pkg install -y git aapt2 ecj d8 apksigner zip unzip python openjdk-17

# что зачем:
#   aapt2      — упаковка ресурсов (AndroidManifest, layout, иконки)
#   ecj        — компилятор Java (Eclipse Compiler for Java)
#   d8         — превращает .class в формат Android (classes.dex)
#   apksigner  — подпись APK
#   zip/unzip  — упаковка
#   python     — выравнивание APK (в Termux нет zipalign, см. п.6)
#   openjdk-17 — нужен для keytool (создание ключа подписи)
```

```bash
# 2. Скачиваем проект
git clone https://github.com/<ваш-логин>/Vizmo.git MobiX
cd MobiX
# (или просто скопируйте папку с проектом в домашнюю папку Termux)

# 3. Собираем
bash build.sh

# 4. Устанавливаем на телефон
bash install.sh
```

`build.sh` делает ровно то же, что Gradle внутри, но по-честному и вручную:

```
res/ ──aapt2 compile/link──▶ APK с ресурсами + сгенерированный R.java
*.java ──javac или ecj──▶ *.class ──d8──▶ classes.dex
APK + classes.dex ──zip──▶ выравнивание (4 байта) ──apksigner──▶ MobiX-IDE-debug.apk
```

Скрипт сам:
* находит `android.jar` (или скачивает платформу Android один раз в `~/.android/android.jar`);
* подставляет атрибут `package="com.mobix.ide.android"` в копию манифеста (в папке `build/`);
* создаёт ключ разработчика `~/.android/debug.keystore` (пароль `android`, алиас `androiddebugkey`),
  если ключа ещё нет — если он уже есть от Android Studio, используется он;
* выравнивает `resources.arsc` (иначе на Android 11+ установка падает);
* подписывает APK и пишет готовый файл в корень проекта.

Полезные переменные (все необязательные):

```bash
MOBIX_MIN_SDK=26 MOBIX_TARGET_SDK=34 bash build.sh      # версии Android
MOBIX_APK_NAME=MyApp.apk bash build.sh                  # имя выходного файла
ANDROID_JAR=/путь/к/android.jar bash build.sh           # свой android.jar
MOBIX_NO_DOWNLOAD=1 bash build.sh                       # не скачивать android.jar
bash build.sh                                           # просто собрать
```

Установка вручную, если `install.sh` не сработал:

```bash
termux-setup-storage          # один раз, дать доступ к памяти
cp MobiX-IDE-debug.apk ~/storage/downloads/
termux-open ~/storage/downloads/MobiX-IDE-debug.apk
# дальше телефон спросит разрешение «Устанавливать из неизвестных источников» → разрешить
```

---

## 3. Сборка через Gradle (если у вас есть Android SDK)

Этот вариант нужен, когда вы хотите подключать библиотеки (AndroidX, Jetpack и т.п.).

```bash
# нужно: JDK 17, Android SDK (platform 34 + build-tools 34)
export ANDROID_HOME=$HOME/android-sdk
cp local.properties.example local.properties     # и поправьте sdk.dir
gradle assembleDebug        # или ./gradlew assembleDebug, если добавите wrapper
# результат: app/build/outputs/apk/debug/app-debug.apk
```

Для сборки **release** раскомментируйте блок `signingConfigs` в `app/build.gradle` и укажите свой ключ:

```bash
keytool -genkeypair -keystore ~/.android/mobix-release.keystore -storetype JKS \
        -alias mobix -keyalg RSA -keysize 2048 -validity 10000
```

В Termux путь к SDK прописывается как
`/data/data/com.termux/files/home/android-sdk` (см. `local.properties.example`).

---

## 4. Что менять в первую очередь

| Что | Где |
|---|---|
| Название на иконке | `app/src/main/res/values/strings.xml` → `app_name` |
| Имя пакета | `app/build.gradle` → `namespace` и `applicationId`; папка `app/src/main/java/com/mobix/ide/android/` |
| Версию | файл `VERSION` (для `build.sh`) и `versionCode`/`versionName` в `app/build.gradle` (для Gradle) |
| Минимальный Android | `minSdk` в `app/build.gradle` и `MOBIX_MIN_SDK` при запуске `build.sh` |
| Чёрный экран / надпись | `app/src/main/res/layout/activity_main.xml` |
| Цвета и тема | `res/values/colors.xml`, `res/values/themes.xml` |
| Логику приложения | `app/src/main/java/com/mobix/ide/android/MainActivity.java` |

Пакет `com.mobix.ide.android` уже прописан в трёх местах и согласован:
`app/build.gradle` (`namespace` + `applicationId`), `build.sh` (`PACKAGE`),
`MainActivity.java` (`package com.mobix.ide.android;`).

---

## 5. Как добавить свою библиотеку

* Без Gradle: положите `.jar` в `app/libs/` и добавьте путь в `build.sh` —
  в строку с `d8` (как в примере: `d8 ... "$SCRIPT_DIR/app/libs/моя-библиотека.jar"`)
  и в `-cp` для компилятора Java.
* С Gradle: `implementation fileTree(dir: 'libs', include: ['*.jar'])` в `app/build.gradle`.

Важно: библиотеки должны быть совместимы с Android, обычные desktop-JAR-ы не подойдут.

---

## 6. Частые проблемы

| Симптом | Решение |
|---|---|
| `нет aapt2 / d8 / apksigner / ecj` | выполните `pkg install aapt2 d8 apksigner ecj zip unzip` |
| `нет android.jar` | просто запустите `bash build.sh` ещё раз (скачает) или положите файл в `~/.android/android.jar` |
| `нет keytool` | `pkg install openjdk-17` |
| Установка не проходит на Android 11+ | соберите заново с `python` (`pkg install python`) — сборка выровняет `resources.arsc`; в Termux нет `zipalign`, поэтому используется `tools/apk_align.py` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | удалите установленную ранее копию с другим ключом подписи |
| Телефон рубит долгие процессы | разрешите Termux работу в фоне (настройки батареи) |
| Gradle падает по памяти | уменьшите `-Xmx` в `gradle.properties` до `1024m` |
| Хочу совсем пустой экран без надписи | удалите `<TextView android:id="@+id/brand" .../>` из `res/layout/activity_main.xml` |

---

## 7. Лицензия

MIT — см. файл `LICENSE`.
