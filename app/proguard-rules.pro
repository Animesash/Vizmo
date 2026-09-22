# Правила ProGuard/R8 для MobiX IDE.
# Сейчас минификация выключена (minifyEnabled false), поэтому файл пустой.
# Если включите minifyEnabled true — добавляйте сюда правила сохранения
# классов, которые находятся через reflection (Activity, View, адаптеры и т.п.).

-keep class com.mobix.ide.android.MainActivity { *; }
