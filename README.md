# ymusic

Неофициальный клиент Яндекс Музыки: ядро на Rust и нативные приложения на SwiftUI — iPhone
(iOS 26, Liquid Glass) и минимальный клиент для Mac.

*Unofficial Yandex Music client: a Rust core with native SwiftUI apps for iPhone and Mac.*

> Проект не связан с Яндексом. Нужен собственный аккаунт; полные треки, высокое качество и
> офлайн сервер отдаёт только при активной подписке Плюс — клиент этого не обходит.

<p align="center">
  <img src="docs/screens/home.jpg" width="24%" alt="Главная с «Моей волной»">
  <img src="docs/screens/player.jpg" width="24%" alt="Плеер">
  <img src="docs/screens/tuning.jpg" width="24%" alt="Настройка «Моей волны»">
  <img src="docs/screens/collection.jpg" width="24%" alt="Коллекция">
</p>
<p align="center">
  <img src="docs/screens/mac.jpg" width="80%" alt="Клиент для Mac">
</p>

## Что умеет

- Главная с «Моей волной» (включая настройку по занятию, характеру, настроению и языку),
  подборки, «Мне нравится», плейлисты, история, поиск.
- Качество на выбор: 64 / 192 / 256 кбит/с AAC и FLAC без потерь, отдельно для Wi‑Fi, сотовой
  сети и загрузок.
- Офлайн: скачивание треков на устройство, режим «Только скачанное», кэш прослушанного.
- Устойчивость к плохой сети: потоковое воспроизведение с докачкой, автоматическое снижение
  качества при слабом соединении и возврат, когда связь восстановилась.
- Анимированная волна на Metal, которая почти ничего не стоит по батарее: ~2 % одного ядра в
  простое, ~0.1 % при воспроизведении в фоне (iPhone 16 Pro).

## Устройство

| Каталог | Что там |
|---|---|
| `core/` | Rust: порт [MarshalX/yandex-music-api](https://github.com/MarshalX/yandex-music-api), наружу через UniFFI |
| `ios/` | Приложение для iPhone; `ios/YaMusic/Core` — общее с Mac ядро воспроизведения, кэша и настроек |
| `mac/` | Приложение для Mac |
| `scripts/` | Сборка, установка на устройство, замеры |

Подробнее об архитектуре — в [CLAUDE.md](CLAUDE.md).

## Сборка

Нужны Xcode 27, Rust с таргетами `aarch64-apple-ios`, `aarch64-apple-ios-sim`,
`aarch64-apple-darwin` и [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
core/build-xcframework.sh                 # ядро → ios/Frameworks/YmCore.xcframework + Swift-биндинги
echo 'YM_TEAM_ID=XXXXXXXXXX' > local.env  # ваш Apple Developer Team ID
scripts/deploy-ios.sh --launch            # собрать и поставить на подключённый iPhone
scripts/build-mac.sh --run                # собрать и запустить на Mac (Debug)
scripts/install-mac.sh --open             # Release-сборка в /Applications (только Apple Silicon)
```

Вход — через OAuth Яндекса внутри приложения.

## Лицензия

LGPL-3.0, как и у исходной библиотеки (см. [LICENSE](LICENSE)).
