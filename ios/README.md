# Арт-Актив — iOS

Нативный клиент интернет-магазина аренды для мероприятий [art-active24.ru](https://www.art-active24.ru/).
SwiftUI (iOS 17+, iPhone), UIKit — точечно там, где он нативнее. Без сторонних зависимостей.

| | |
|---|---|
| Bundle ID | `ru.artactive24.app` |
| Имя | «Арт-Актив» (en — «Art-Active») |
| Минимум | iOS 17.0, только iPhone |
| Сборка | Xcode 26 (SDK iOS 26 — Liquid Glass), XcodeGen |
| API | `contract/openapi.yaml` — единственный источник правды по DTO |

## Структура

```
ios/
├── project.yml                 XcodeGen: таргеты ArtActive + ArtActiveTests, схема ArtActive
├── ArtActive/
│   ├── App/                    @main, AppDelegate (push), DI-контейнер, роутер, deep links, RootView (TabView)
│   ├── Data/                   APIClient (конверт, ошибки, refresh токенов, офлайн-кэш), DTO по контракту,
│   │                           репозитории (протокол + Live), Keychain, SessionManager, LocalStore, NetworkMonitor
│   ├── Domain/                 Pricing (формулы DATA-MODEL.md), Configurator (логика карточки 128),
│   │                           сторы: Auth, Cart, Favorites, RecentlyViewed, SearchHistory, Orders, Info, Push
│   ├── DesignSystem/           токены (светлая + тёмная палитры), шрифты Golos/Inter, Haptics, Liquid Glass,
│   │   └── Components/         кнопки, чипы, степпер, сегмент времени, ползунок, карточки, галерея, skeleton…
│   │       └── UIKit/          UIScrollView-зум, UITextField (маска телефона, oneTimeCode), AVPlayerViewController, Safari
│   ├── Features/               Home, Catalog, Category, Search, Product (+Configurator, Templates), Venues,
│   │                           Cart, Checkout, Auth, Profile (заказы, данные, инфо), Favorites
│   ├── PreviewContent/         фикстуры JSON + репозитории на фикстурах для Previews (только Debug)
│   └── Resources/              Info.plist, entitlements, Assets.xcassets, Fonts, Localizable.xcstrings, InfoPlist.xcstrings
├── ArtActiveTests/             XCTest: все векторы contract/pricing-vectors.json, конфигуратор, DTO/фикстуры, форматтеры
└── tools/                      build-assets.mjs (иконки/шрифты/AppIcon), extract-strings.mjs (String Catalog)
```

Слои: `Data → Domain → Features`. ViewModel — `@Observable @MainActor`, состояния
`loading / content / empty / error`; бизнес-логики во View нет (цена и выбор — `Configurator` + `Pricing`).

## Сборка в CI (основной способ — на Windows Swift не собирается)

Workflow `.github/workflows/ios.yml` в корне репозитория запускается при push с изменениями в
`ios/**`, `contract/**` или самого workflow, а также вручную (Actions → *iOS — build, test, unsigned IPA* → Run workflow).

Шаги: выбор Xcode 26 на `macos-15` → проверка String Catalog (ru+en) → `xcodegen generate` →
сборка под симулятор → **XCTest** (все векторы цены из `contract/`, фикстуры, конфигуратор) →
Release-сборка под устройство без подписи → артефакт **`ArtActive-unsigned-ipa`** (`ArtActive.ipa`).
При падении тестов выкладывается `ArtActive-test-results` (xcresult).

Локально на Mac:

```bash
brew install xcodegen
cd ios && xcodegen generate && open ArtActive.xcodeproj
```

## Установка на iPhone через Sideloadly

1. Скачайте артефакт `ArtActive-unsigned-ipa` из запуска workflow, распакуйте `ArtActive.ipa`.
2. Откройте [Sideloadly](https://sideloadly.io/), подключите iPhone кабелем, перетащите `.ipa`.
3. Введите Apple ID (бесплатный подойдёт) → Start. Sideloadly переподпишет приложение.
4. На iPhone: Настройки → Основные → VPN и управление устройством → доверять разработчику.
   На iOS 16+ включите «Режим разработчика» (Настройки → Конфиденциальность и безопасность).

С бесплатным Apple ID подпись живёт 7 дней; push и universal links при такой подписи не работают
(нужны capability платного аккаунта — см. ниже). Всё остальное работает.

**Адрес API.** Debug смотрит на `http://127.0.0.1:8080` (локальный `api/`, `Config/Debug.xcconfig`).
Боевой адрес в публичном репозитории **не хранится**: Release берёт `API_BASE_URL` из
`Config/Secrets.xcconfig` (в .gitignore), который CI создаёт из секрета репозитория
**`API_BASE_URL`** (Settings → Secrets and variables → Actions), например `https://<домен>/<путь-API>/`.
Без секрета сборка проходит с плейсхолдером `https://api.invalid/api/` и предупреждением в логе.
Локально: создайте `ios/Config/Secrets.xcconfig` со строкой
`API_BASE_URL = https:/$()/<домен>/<путь-API>/` (в xcconfig «//» — комментарий, отсюда `/$()/`).
Значение попадает в Info.plist (`APIBaseURL`) → `AppConfig.apiBaseURL`.

## Push-уведомления (APNs)

Код готов: запрос разрешения после входа/заказа, `registerForRemoteNotifications`, токен →
`POST /v1/me/devices {platform:"ios", token}`, тап по уведомлению с `orderId` открывает заказ,
в foreground показывается баннер и обновляется «Мои заказы».

Включение (платный Apple Developer):
1. developer.apple.com → Identifiers → `ru.artactive24.app` → включить **Push Notifications**.
2. Keys → создать APNs Auth Key (.p8) → отдать бэкенду (Key ID, Team ID, bundle id).
3. В `project.yml` указать `DEVELOPMENT_TEAM`; entitlements уже подключены
   (`ArtActive/Resources/ArtActive.entitlements`: `aps-environment`). Для App Store — `production`.
4. Payload сервера: `{"aps":{"alert":{...},"sound":"default"},"orderId":123}`.

CI собирает без подписи и с `CODE_SIGN_ENTITLEMENTS=""` — поэтому unsigned-сборка проходит.

## Universal links

Ссылки `https://www.art-active24.ru/...` открывают приложение; путь разбирает сервер
(`GET /v1/resolve?path=`) → товар (с предвыбором комплекта/варианта/аренды-покупки), раздел, площадка;
неизвестное — Safari внутри приложения. Также схема `artactive24://product/123`, `…/category/81`,
`…/venue/5`, `…/order/42`.

Включение:
1. Identifier → **Associated Domains**; entitlement уже содержит
   `applinks:www.art-active24.ru`, `applinks:art-active24.ru`.
2. На сайте разместить `https://www.art-active24.ru/.well-known/apple-app-site-association`
   (без расширения, `application/json`):
   ```json
   {"applinks":{"details":[{"appIDs":["<TEAMID>.ru.artactive24.app"],"components":[{"/":"/*"},{"/":"/images/*","exclude":true}]}]}}
   ```

## Подпись релиза (App Store / TestFlight)

1. `project.yml`: `DEVELOPMENT_TEAM: <TEAMID>`, при необходимости `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`.
2. `xcodegen generate`, в Xcode: Product → Archive → Distribute App → App Store Connect.
3. Для CI-подписи: добавить в секреты сертификат (.p12) и профиль, импортировать в keychain раннера
   (`apple-actions/import-codesign-certs`) и собрать `xcodebuild archive` + `-exportArchive`
   с `ExportOptions.plist` (`method: app-store-connect`). Unsigned-шаг можно оставить для Sideloadly.
4. `aps-environment` в entitlements → `production`.

## Дизайн и платформа

- **Системный язык iOS**: TabView (на iOS 18+ — Tab API), NavigationStack с large titles и свайпом назад,
  `.searchable`, шиты с `presentationDetents`, `Menu`/`contextMenu` (long-press превью), `swipeActions`,
  `.refreshable`, системные DatePicker/Picker, SF Symbols в таб-баре.
- **Liquid Glass** (iOS 26): системные бары — автоматически; свои плавающие элементы (липкий бар цены,
  кнопки поверх фото/видео, плавающие фильтры, Undo-тост) — `.glassEffect` / `GlassEffectContainer`
  под `if #available(iOS 26, *)`, на iOS 17–25 — `.ultraThinMaterial` (`DesignSystem/Glass.swift`).
- **Айдентика** поверх HIG: акцент `#705ABF` через `.tint`, Golos Text (общие экраны) и Inter (карточка товара),
  радиусы/тени/компоненты из токенов айдентики (локальный `research/brand/tokens.json`). Шрифты — те же OFL-семейства, статические TTF
  400/500/600/700 (сайт отдаёт woff2-сабсеты, которые нельзя зарегистрировать в iOS под одним именем).
- **Тёмная тема** — палитра выведена из айдентики (`Palette`, динамические цвета).
- **Тактильность** — словарь `docs/UX.md` в `Haptics` (+`prepare()` перед жестами), анимации уважают Reduce Motion,
  Dynamic Type (`Font.custom(_:size:relativeTo:)`), VoiceOver-подписи.
- **Локализация** — `Localizable.xcstrings` (ru — язык разработки, en), плюралы (1 день / 2 дня / 5 дней),
  цены `FormatStyle.currency(code: "RUB")`, даты — `Locale.current`.
  После правки строк: `cd ios/tools && node extract-strings.mjs` (новые ключи → `strings-en.json`).

## Ресурсы

`cd ios/tools && npm install && node build-assets.mjs` — пересобирает из локальной папки `research/brand/assets`
(исследование айдентики; в публичный репозиторий не входит):
иконки шапки/таб-бара (SVG, `preserves-vector-representation`, template), логотипы, AppIcon 1024
(из favicon.svg), шрифты. Результат уже лежит в репозитории.

## Тесты

`ArtActiveTests`:
- `PricingVectorTests` — **все** векторы `contract/pricing-vectors.json` (файл подключён ресурсом из `contract/`
  в `project.yml`, не копия), включая ожидаемые ошибки валидации (`expect.error`), округление
  `floor(x + 0.5 + 1e-9)`, обязательные допы.
- `ConfiguratorTests` — стол «Виктория 180» (дни, подсказка «с 2-го дня»), плов (группы вариантов, минимум,
  доп один раз), батут (обязательные барьеры, асфальт +10 000 не × время, «Купить» без времени и установки,
  вариант-URL), мастер-класс, кейтеринг-меню (minQty).
- `DataLayerTests` — декодирование фикстур по контракту, неизвестные enum, опущенные ключи, маска телефона,
  HTML-парсер, параметры фильтров площадок.
