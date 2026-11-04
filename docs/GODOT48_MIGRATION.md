# Godot 4.8-beta2 migration / Переход на Godot 4.8-beta2

ATLAS 0.1.1 uses the official Godot 4.8-beta2 standard editor and matching Windows/Android templates, pinned by SHA-512 archive and SHA-256 extracted-file hashes. The review covers all nine 4.8 snapshots available through beta2: dev1–dev7, beta1 and beta2. It uses the release articles, the complete interactive changelog (1,665 merged PR records), and beta2's class reference/source. It is not a line-by-line audit of the entire engine. Save/network schemas and Android package/signing identity are unchanged. This is a prerelease engine build; real Android hardware and production deployment remain unverified.

## Что изменено в игре

- **ПК и Android:** редактор, Windows-шаблон и оба Android-шаблона закреплены за `4.8-beta2`, коммит `cafc17a192acf67903910a68aeb3c076c0907a4b`. Исходный VPS Dockerfile обновлён до той же версии, поскольку он собирает общий GDScript-код клиента и сервера.
- **Сборка:** `tools/godot_release.json` фиксирует официальные архивы и контрольные суммы. Установщик проверяет существующие редактор/шаблоны перед использованием, восстанавливает старые или повреждённые файлы и отклоняет повреждённые загрузки. Файлы 4.7.2 не переиспользуются в новой сборке.
- **Поиск стран:** обе страницы используют нативный `FuzzySearch`, понимающий пропущенные буквы; русские и английские названия доступны независимо от языка интерфейса. Пустой запрос сохраняет полный алфавитный список, непустой показывает совпадения по релевантности. ID остаются привязаны к исходным странам через `original_index`.
- **Звуки интерфейса:** `BaseButton` получает `pressed_sound`, `pressed_disabled_sound` и `focus_sound` из общей темы. Удалены ручные обработчики звука обычного нажатия, включая дублирующий обработчик полноэкранного режима. Шина `Interface` с уровнем −13 дБ направлена в `Effects`, поэтому существующие настройки общей громкости и эффектов продолжают действовать. Звуки игровых событий сохраняют отдельное семантическое управление.
- **Заголовки карточек:** `Label.resize_font_to_fit` подбирает размер между 16 и 22; полное название доступно в подсказке. Минимальная высота зафиксирована, чтобы контейнер мог выделить место для читаемого текста.
- **Вёрстка HUD:** сумма денег и доход явно используют однострочные Label. Это исправляет обнаруженное при визуальной проверке сжатие панели казны новым алгоритмом размеров контейнеров 4.8; перенос остаётся включённым для обычного текста меню.
- **Мобильные переходы:** сохраняются анимации 180 мс, отмена предыдущей анимации и отсутствие повторного появления при обновлении той же страницы.
- **Распространение:** версия приложения 0.1.1, Android versionCode 12; ID `org.byxarek.atlas`, прежний ключ подписи, каталоги пользовательских данных и форматы сохранений не менялись. Новая Windows-сборка лежит отдельно в `build/windows-v0.1.1`.

## Разбор всех dev- и beta-снимков

Каждая строка ссылается на официальный выпуск. Изменения движка, не требующие вызова нового API, приходят с обновлёнными бинарниками.

| Снимок | Что изучено | Применение к ATLAS |
| --- | --- | --- |
| [dev1](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-1/) | FuzzySearch, touch в TextEdit/CodeEdit, sticky Tree, псевдолокализация редактора, Mbed TLS 4.1/PSA Crypto | FuzzySearch внедрён; TLS приходит с движком. Игра не использует CodeEdit и Tree |
| [dev2](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-2/) | Ускорение удаления множества дочерних узлов, сериализация Object с переносами строк, устойчивость завершения GDScript | Полезно динамически создаваемым меню без изменения форматов игровых JSON-сохранений |
| [dev3](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-3/) | Исправление нагрузки от мышей с высокой частотой опроса Windows, диагностика GDScript, настройка TabBar | Исправление ввода приходит с движком; TabBar в текущем интерфейсе нет |
| [dev4](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-4/) | Автоподбор шрифта Label/RichTextLabel, Android/Java SDK manager, GDType, Trail3D и decals Compatibility | Автоподбор внедрён по реальному API beta2; существующая настройка SDK для командной сборки сохранена |
| [dev5](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-5/) | Mip-level streaming, alpha coverage, новый фокус Control, SpinBox.format, оптимизация памяти GDType | Новый фокус и оптимизации приходят с движком. Карта векторная; текстурный streaming для неё не включён |
| [dev6](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-6/) | Контактные тени, 3D-редактор, ускорение подсветки GDScript, регрессия OpenXR spatial container | 3D/XR не используются; не добавлены ради обновления версии |
| [dev7](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-7/) | GUI theme sounds, touch PopupMenu/TabBar, AccessKit Android/iOS, неаллоцирующие physics queries, Variant conversions, AAR export | Theme sounds внедрены. PopupMenu селекторов и Android accessibility используют поддержку движка. Физических запросов и AAR-интеграции в игре нет |
| [beta1](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/) | Общий перечень возможностей 4.8 и breaking changes, фиксация возможностей, уменьшение бинарников | Сопоставлены используемые API и конфигурации; несовместимые 3D/C#/GDExtension-возможности игре не нужны |
| [beta2](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/) | 144 исправления: видимая область touch-кнопок, Compatibility multiply blending, Unicode 18, исправления контейнеров и ресурсов | Используется именно beta2, а не ранняя dev; выполнены проверки вёрстки, ввода и экспорта |

## Изменения API и совместимости

Сверка выполнена с [полным changelog 4.8](https://godotengine.github.io/godot-interactive-changelog/#4.8) и классами из точного коммита beta2.

- Ранние статьи называют свойства автоподбора `auto_font_size`, `min_font_size`, `max_font_size`. В [Label beta2](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/Label.xml) используются **`resize_font_to_fit`, `minimum_font_size`, `maximum_font_size`**. Код использует последние.
- [FuzzySearch](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/FuzzySearch.xml) помечен experimental: используем только `search_all`, `max_results` и `original_index`, с фиксированным движком и тестами кириллицы, опечатки и пустого результата.
- [Theme sounds](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/BaseButton.xml) обслуживаются движком для мыши, клавиатуры и touch. `ProjectSettings.audio/buses/gui_theme_bus` направляет их на шину интерфейса. Простая ручная эмиссия сигнала `pressed` не заменяет настоящий ввод; тест использует новый `BaseButton.press()`.
- У SpinBox устаревают `prefix`/`suffix` в пользу `format`; в текущем коде ATLAS эти свойства не используются, переписывать поля не требуется.
- Изменены стандартные заголовки диалогов. Игра явно задаёт содержательные заголовки подтверждений и сообщений; они сохранены.
- `OS.alert()` на Android стал блокирующим; игра использует `AcceptDialog`/`ConfirmationDialog`, поэтому этот вызов не добавлен.
- Исправлены дублирующиеся нажатия touch и обработка кнопок вне видимой области. Дополнительная проверка настоящего touch-события выполняется в оконном тесте UI; headless-тест не имитирует нативную систему касаний.
- Изменения ScriptServer/ClassDB, запрет наследования собственной внутренней реализации, 3D enter_world, LookAtModifier3D, BoneFollower, XR constants и ASTC-профили не затрагивают используемые пути. Игра импортируется и исполняется на beta2 без адаптеров старых API.
- Новый TLS-стек требует проверки реального HTTPS/WSS и цепочек сертификатов при развёртывании. Локальные сетевые тесты не подтверждают соединение с каждым production-провайдером.

## Библиотеки комплекта

Источники: [thirdparty/README.md beta2](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/thirdparty/README.md) и [Android config.gradle](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/platform/android/java/app/config.gradle). Это версии официального комплекта; они не объявляются последними отдельными upstream-релизами.

| Компонент | Godot 4.7.2 | Godot 4.8-beta2 |
| --- | --- | --- |
| Mbed TLS | 3.6.7 | 4.1.1, PSA Crypto |
| HarfBuzz | 14.2.0 | 14.4.0 |
| libpng | 1.6.58 | 1.6.59 |
| ICU | 78.3 | 79.1 |
| AccessKit C | 0.22.3 | 0.23.1 |
| Graphite | 1.3.14 | 1.3.15 |
| PCRE2 | 10.47 | 10.49 |
| SDL | 3.2.28 | 3.4.12 |
| ThorVG | 1.0.3 | 1.1.3 |
| Clipper2 | 1.5.4 | 2.0.1 |
| Android Gradle Plugin | 8.6.1 | 8.13.2 |

Обновились также certs, Jolt 5.6.0, Manifold 3.5.2, Meshoptimizer 1.2, OpenXR 1.1.63, TinyEXR 3.2.0 и ufbx 0.23.1; добавлен offset_allocator. Наличие компонента в исходниках Godot не означает, что игра его использует. FreeType 2.14.3, Kotlin 2.1.21, AndroidX Fragment 1.8.6 и SplashScreen 1.0.1 в официальном beta2 остаются прежними. Самовольная замена отдельных библиотек означала бы отдельную сборку и проверку самого движка; здесь используется официальный релиз пользователя.

Лицензия и COPYRIGHT beta2 обновлены в `tools` и `assets/legal`, включая файлы, встроенные в APK и Windows-архив. Android продолжает использовать готовые APK-шаблоны без локальной Gradle/NDK-пересборки.

## Проверки и оставшиеся ограничения

Полная сборка: `tools/build.ps1`. Она проверяет контрольные суммы, импорт, переводы, установщик, симуляцию, военные правила, звук, UI, мобильную вёрстку, ENet/discovery, VPS, PHP и экспортирует Windows и Android. Оконные UI/мобильные/аудиопроверки запускаются отдельно для реального рендера, touch-обработки и аудиомикшера.

Не добавлены 3D-тени, Trail3D, XR, C#, AAR и texture streaming: они не участвуют в нынешней 2D-игре. Это миграция затронутых путей и внедрение полезных API, а не изменение игровых правил или замена работающей симуляции ради другой записи того же кода.

Godot 4.8-beta2 остаётся предварительным выпуском. Проверки не заменяют физический Android, долгую партию под нагрузкой, проверку системной клавиатуры/поворота и production HTTPS/WSS. Обновления на FTP и публикации релиза в рамках локальной миграции не выполняются.

Список открытых регрессий 4.8 дополнительно проверен 4 ноября 2026 года через официальный GitHub issue tracker. Для последующих испытаний важны [управление fullscreen на Windows](https://github.com/godotengine/godot/issues/125049) и [появление системной панели Android после касания на отдельных устройствах](https://github.com/godotengine/godot/issues/122721); это сообщения о движке, а не подтверждённые ошибки ATLAS. Локальный оконный тест переключения fullscreen проходит. [Регрессия touch при stretch aspect `keep`](https://github.com/godotengine/godot/issues/125141) описывает другую конфигурацию: ATLAS использует `expand`. [Сбой прямого Java-вызова getRootWindowInsets](https://github.com/godotengine/godot/issues/124123) касается пути AndroidRuntime, который игра не использует; safe area получается через DisplayServer.
