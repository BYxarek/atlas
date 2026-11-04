# Сторонние материалы

## Godot Engine 4.7.2

Игра использует Godot Engine, распространяемый по лицензии MIT.

- Официальный сайт: https://godotengine.org/
- Лицензия: https://github.com/godotengine/godot/blob/4.7.2-stable/LICENSE.txt
- Уведомления о компонентах: https://github.com/godotengine/godot/blob/4.7.2-stable/COPYRIGHT.txt

Полный текст лицензии и уведомления включены в Windows-архив как `GODOT-LICENSE.txt` и `GODOT-COPYRIGHT.txt`.

## Natural Earth

Границы стран: Natural Earth, Admin 0 Countries, масштаб 1:110m. Данные находятся в общественном достоянии (public domain).

- https://www.naturalearthdata.com/about/terms-of-use/
- Источник: https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_110m_admin_0_countries.geojson

Данные преобразованы скриптом `tools/prepare_map.py`: исключена Антарктида, внешние контуры округлены до 0,001 градуса, добавлены идентификаторы, центры и соседство. Подготовленная карта хранится в `assets/world.json`.

Иконка ATLAS и интерфейс созданы для этого проекта. Внешние шрифты и изображения не включены; используется встроенный шрифт Godot.

## Звуки — CC0 1.0

Все использованные звуки опубликованы авторами под Creative Commons Zero 1.0: https://creativecommons.org/publicdomain/zero/1.0/

| Набор | Автор | Оригинал |
|---|---|---|
| Interface Sounds | Kenney | https://kenney.nl/assets/interface-sounds |
| RPG Audio | Kenney | https://kenney.nl/assets/rpg-audio |
| Sci-fi Sounds | Kenney | https://kenney.nl/assets/sci-fi-sounds |
| Music Jingles | Kenney | https://kenney.nl/assets/music-jingles |
| Tiny Naval Battle Sounds Set | Iwan Gabovitch / qubodup | https://opengameart.org/content/tiny-naval-battle-sounds-set |
| Explosions | EZduzziteh | https://opengameart.org/content/explosions-4 |
| Short alarm | yd | https://opengameart.org/content/short-alarm |
| Frequency Static Sound Effects | bretbernhoft | https://opengameart.org/content/frequency-static-sound-effects |

Изменения для ATLAS: выбор коротких фрагментов, сведение составных эффектов, повторы шагов, нормализация пиков, плавные края, перевод в mono и сжатие в Ogg Vorbis. Создан 31 файл общим объёмом 348 318 байт. Исходные имена файлов и SHA-256 задокументированы в `assets/audio/manifest.json`; оригинальные тексты лицензий Kenney и README qubodup — в `assets/audio/licenses`. Лицензии и манифест также включены в Windows-архив в папке `Audio-Licenses`.


## Источник калибровки военного баланса

Порядок военной силы стран сверён с Global Firepower 2026 (проверено 3 ноября 2026): https://www.globalfirepower.com/countries-listing.php

В игру включены собственные условные численности армий, полученные для игрового баланса. Они не являются официальными показателями GFP, реальными численностями армий или воспроизведением PowerIndex. Исходная таблица рейтинга, тексты и логотип GFP в игру не включены.
