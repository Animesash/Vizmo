# Vizmo

Минимальное Android-приложение: один экран, полностью чёрный фон.

## Параметры

| Параметр | Значение |
|---|---|
| Название приложения | **Vizmo** |
| Пакет | `com.vizmo.android` |
| Минимальная версия | Android 8.0 (API 26) |
| Target / Compile SDK | Android 15 (API 35) |
| Язык | Kotlin |

## Структура

```
Vizmo/
├── app/
│   └── src/main/
│       ├── AndroidManifest.xml          # манифест приложения
│       ├── java/com/vizmo/android/
│       │   └── MainActivity.kt          # главный экран (пустой, фон из темы)
│       └── res/
│           ├── values/                  # строки, цвета, тема (чёрный фон)
│           ├── drawable/                # векторная иконка
│           └── mipmap-anydpi-v26/       # адаптивные иконки лаунчера
├── build.gradle.kts                     # плагины и их версии
├── settings.gradle.kts                  # модули и репозитории
├── gradle.properties                    # настройки Gradle
├── gradle/wrapper/                      # Gradle Wrapper 8.9
└── gradlew / gradlew.bat                # скрипты сборки (Linux/macOS, Windows)
```

Чёрный цвет экрана задаётся темой `Theme.Vizmo` (`app/src/main/res/values/themes.xml`),
поэтому разметка экрана не нужна.

## Сборка

### Вариант 1 — Android Studio (рекомендуется)

1. Установите [Android Studio](https://developer.android.com/studio) (Ladybug или новее).
2. **File → Open** → выберите папку проекта `Vizmo`.
3. Дождитесь синхронизации Gradle (интернет нужен для скачивания зависимостей).
4. **Build → Build App Bundle(s) / APK(s) → Build APK(s)** — или просто нажмите ▶ для запуска на эмуляторе/устройстве.

### Вариант 2 — из командной строки

Требуется JDK 17+ и Android SDK (переменная `ANDROID_HOME`; если Android Studio установлена,
SDK обычно лежит в `%LOCALAPPDATA%\Android\Sdk` на Windows или `~/Android/Sdk` на Linux/macOS).
Файл `local.properties` со строкой `sdk.dir=...` Gradle создаст сам при сборке из Android Studio;
для командной строки создайте его вручную при необходимости.

```bash
./gradlew assembleDebug        # Linux/macOS
gradlew.bat assembleDebug      # Windows
```

Готовый APK: `app/build/outputs/apk/debug/app-debug.apk`

### CI

При каждом push в `main` GitHub Actions автоматически собирает debug-APK
(см. `.github/workflows/android-build.yml`) — APK доступен в артефактах сборки.
