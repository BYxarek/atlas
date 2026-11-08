# Сторонние материалы

## Godot Engine 4.8-beta2

Игра использует Godot Engine, распространяемый по лицензии MIT.

- Официальный сайт: https://godotengine.org/
- Лицензия: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/LICENSE.txt
- Уведомления о компонентах: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/COPYRIGHT.txt

Полный текст лицензии и уведомления включены в Windows-архив как `GODOT-LICENSE.txt` и `GODOT-COPYRIGHT.txt`.

## Natural Earth

Границы стран: Natural Earth, Admin 0 Countries, масштабы 1:110m (основа) и 1:10m (добавленные малые государства и территории). Данные находятся в общественном достоянии (public domain).

- https://www.naturalearthdata.com/about/terms-of-use/
- Источник: https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_110m_admin_0_countries.geojson

Данные преобразованы скриптом `tools/prepare_map.py`: исключена Антарктида, внешние контуры округлены до 0,001 градуса, добавлены идентификаторы, центры и соседство. Подготовленная карта хранится в `assets/world.json`.

## Природный слой Земли

- Цвет суши: NASA Earth Observatory, Blue Marble Next Generation, снимки за июль 2004 года. https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/base-map/
- Реки и озёра: Natural Earth 1:10m, версия 5.1.2, данные в общественном достоянии. https://www.naturalearthdata.com/downloads/10m-physical-vectors/
- Лесной покров: NASA Earthdata GIBS, MODIS Combined Land Cover Type, классификация IGBP за 2022 год. https://gibs.earthdata.nasa.gov/layer-metadata/v1.0/MODIS_Combined_L3_IGBP_Land_Cover_Type_Annual.json

Текстуры для проекции атласа подготовлены скриптом `tools/prepare_nature.py`.

## NOAA ETOPO 2022

Высоты и глубины для 2.5D-карты основаны на глобальной модели NOAA National Centers for Environmental Information (NCEI) ETOPO 2022, версия Ice Surface с шагом 60 угловых секунд. Набор общедоступен. Скрипт `tools/prepare_relief.py` создаёт из него компактную текстуру `assets/earth_relief.png` с интервалом 1 градус.

- https://www.ncei.noaa.gov/products/etopo-global-relief-model
- https://doi.org/10.25921/fd45-gt74

Иконка ATLAS и интерфейс созданы для этого проекта. Для текста используется встроенный шрифт Godot.

Дополнения Natural Earth 1:10m и связи подчинения: tools/map_additions.json. Источник: https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_10m_admin_0_countries.geojson. Военные базы и неопределённые участки из дополнений исключены; исходные 176 идентификаторов сохранены. Ниуэ и Острова Кука оставлены самостоятельными согласно описанию свободной ассоциации МИД Новой Зеландии: https://www.mfat.govt.nz/en/countries-and-regions/australia-and-pacific/niue и https://www.mfat.govt.nz/en/countries-and-regions/australia-and-pacific/cook-islands.

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
