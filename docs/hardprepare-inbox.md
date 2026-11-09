# HardPrepare Inbox

Персональный форк [Mithka](https://github.com/iebb/mithka), клиента Telegram на Flutter и TDLib для macOS и Android.

## Как получить подсказку

1. Откройте личный чат с клиентом. На Mac нажмите лампочку над полем сообщения. На Android откройте **+ → HardPrepare**.
2. Опишите вопрос своими словами. Добавьте только известные детали, например «Ученик спрашивает о пробном NUET. Точную цену уточню. Спроси, когда ему удобно».
3. Нажмите **Подсказать**. Проверьте ответ и нажмите **Вставить**. Если в поле уже есть черновик, подсказка добавится в конец. Дальше ответ можно править и отправить обычной кнопкой Telegram.

Функция отправляет модели только введённый бриф и инструкцию HardPrepare. Данные чата и история в запрос не входят. Для брифа используйте краткое описание без цитат и персональных данных клиента. Условия Telegram отдельно регулируют обработку материалов платформы моделями. [Условия Telegram](https://telegram.org/tos/content-licensing)

## Вход в рабочий аккаунт

При первом запуске откройте **API Credentials** и укажите `api_id` и `api_hash` приложения из [my.telegram.org](https://my.telegram.org). Затем войдите в рабочий аккаунт по QR или номеру телефона. Каждому устройству нужна своя авторизация.

Mithka поддерживает импорт строки GramJS в разделе резервного копирования аккаунта. Для действующей серверной сессии HardPrepare используйте вход по QR или номеру. Параллельное использование одного ключа авторизации может привести к его отзыву. [Ошибка AUTH_KEY_DUPLICATED](https://core.telegram.org/api/errors#406-not-acceptable)

## Модель

По умолчанию подсказка работает с Ollama на `127.0.0.1:11434`. Запустите Ollama и загрузите модель `qwen2.5:3b` командой `ollama pull qwen2.5:3b`.

На подключённом по USB Android для доступа к Ollama на Mac выполните `adb reverse tcp:11434 tcp:11434`. Для работы телефона без USB откройте **Settings → AI → Providers** и сохраните адрес своего HTTPS-сервиса и ключ, затем добавьте модель через **Models**. Подсказка использует последнюю сохранённую серверную модель. Поддерживаются Ollama, OpenAI Chat Completions, OpenAI Responses и Anthropic Messages. Перед генерацией диалог показывает адрес и название модели.

## Сборка

Используйте Flutter 3.44.2, Android SDK 36 с NDK 28.2.13676358 и Xcode. Для локальной сборки можно скопировать `lib/config/secrets_example.dart` в `lib/config/secrets.dart` и указать реквизиты в приложении после запуска.

```bash
flutter config --enable-swift-package-manager
flutter pub get
scripts/build-tdjson-android.sh arm64-v8a
scripts/build-tdjson-desktop.sh macos native-libs/libtdjson.dylib
sh scripts/refresh-apple-mdk.sh refresh
flutter build apk --release --target-platform android-arm64
flutter build macos --release
```

Подробности по TDLib и сборкам находятся в [NATIVE.md](../NATIVE.md) и [README Mithka](../README.md#build-from-source).
