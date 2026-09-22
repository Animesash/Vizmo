package com.mobix.ide.android;

import android.app.Activity;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;

/**
 * Главный (и пока единственный) экран MobiX IDE.
 *
 * Задача этого файла — быть «каркасом» любого проекта:
 *   • активность наследуется от android.app.Activity (без AndroidX),
 *   • экран полностью чёрный (см. res/layout/activity_main.xml и themes.xml),
 *   • статус-бар и панель навигации тоже чёрные.
 *
 * Дальше код можно наращивать: редактор кода, список файлов, кнопка «Собрать»
 * — каркас для этого уже готов (см. комментарии с TODO).
 */
public final class MainActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        makeSystemBarsBlack();

        // Разметка экрана: чёрный фон во весь экран.
        // Если хотите абсолютно пустой чёрный экран — просто удалите из
        // activity_main.xml дочерние View (файл уже почти пустой).
        setContentView(R.layout.activity_main);

        // TODO: здесь подключается будущий IDE-интерфейс, например:
        //   ViewGroup content = findViewById(R.id.content);
        //   content.addView(new CodeEditorView(this));
    }

    /**
     * Делает статус-бар и панель навигации чёрными и убирает
     * автоматическое затемнение системных полос.
     */
    private void makeSystemBarsBlack() {
        Window window = getWindow();
        window.setBackgroundDrawableResource(R.color.black);
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS);
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
        window.setStatusBarColor(getColor(R.color.black));
        window.setNavigationBarColor(getColor(R.color.black));

        // Приложение всегда тёмное — системные иконки делаем светлыми.
        int flags = window.getDecorView().getSystemUiVisibility();
        flags &= ~View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;          // API 23+
        flags &= ~View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;      // API 26+
        window.getDecorView().setSystemUiVisibility(flags);
    }
}
