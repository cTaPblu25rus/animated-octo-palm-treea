# Сторонние ассеты

Все модели ниже распространяются по лицензии **CC0** (общественное достояние):
можно использовать в коммерческих проектах, указывать автора не обязательно.
Тексты лицензий лежат рядом с файлами в `assets/kaykit/*/LICENSE.txt`.

| Набор | Автор | Что используем | Источник |
|---|---|---|---|
| KayKit Character Pack: Skeletons 1.0 | Kay Lousberg | скелеты с анимациями, клинок, топор | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0 |
| KayKit Dungeon Remastered 1.0 | Kay Lousberg | стены, пол, факелы, сундук, бочки, знамёна | https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0 |
| KayKit Character Pack: Adventurers 1.0 | Kay Lousberg | меч и щит героя | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 |

| Poly Haven: Castle Brick 07, Cobblestone Floor 08 | Poly Haven | камень стен и пола в реалистичном стиле | https://polyhaven.com/a/castle_brick_07 · https://polyhaven.com/a/cobblestone_floor_08 |

## Озвучка
Реплики в `assets/voice/` синтезированы программой [Piper](https://github.com/OHF-Voice/piper1-gpl)
голосами `ru_RU-dmitri-medium` (рассказчик) и `ru_RU-denis-medium` (босс, понижен и с эхом).
Оба голоса обучены на датасете с лицензией CC0. Тексты — в `data/voice.json`,
пересборка: `python3 tools/make_voice.py <папка с моделями>`.

Это временная графика для прототипа. Свой визуальный стиль (см. `docs/GDD.md`,
раздел «Арт») делаем позже и заменяем модели по одной.
