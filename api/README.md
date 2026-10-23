# Art-Active24 App API

REST API мобильного приложения. PHP 8.1+, без фреймворка, зависимости — только PHPUnit для тестов.
Контракт: `../contract/openapi.yaml`. Архитектура: `../docs/ARCHITECTURE.md`.

## Локальный запуск

```bash
cd api
cp .env.example .env            # AUTH_PEPPER — любая длинная строка; MANAGER_PHONES — ваш номер
php composer.phar install
php bin/migrate.php             # создаёт var/app.sqlite и таблицы app_*
php -S 127.0.0.1:8080 -t public public/index.php
```

Каталог в dev берётся из снапшота `data/snapshot/` (собирается `tools/snapshot`, см. его README).
Для быстрого старта можно указать `SNAPSHOT_DIR=tests/fixtures/snapshot` — маленький набор товаров.
SMS-коды в dev не отправляются, а пишутся в `var/log/sms.log`.

Эмулятор Android видит сервер как `http://10.0.2.2:8080`, симулятор iOS — `http://127.0.0.1:8080`.

> Боевые адреса, ключи и токены в репозиторий не попадают: только в `.env` на сервере и в секретах CI.

## Тесты

```bash
php vendor/bin/phpunit            # unit + integration (SQLite в памяти, снапшот-фикстура)
```
`tests/Unit/PriceCalculatorTest` прогоняет общие эталонные примеры `contract/pricing-vectors.json` —
те же, что тесты iOS и Android, поэтому цена совпадает на всех трёх платформах.

## Устройство

| Папка | Что |
|---|---|
| `src/Http` | Request/Response (конверт `{success,data,error,meta}`), Router, контроллеры, middleware авторизации |
| `src/Pricing` | `CartItem` (валидированная позиция), `PriceCalculator` (формула сайта 1-в-1) |
| `src/Catalog` | интерфейсы `CatalogRepository`, `VenueRepository`, `ContentRepository`; `Snapshot/*` — реализация на снапшоте |
| `src/Cart` | `QuoteService` — серверный пересчёт корзины; `CartRepository` — корзина пользователя |
| `src/Auth` | вход по SMS: `PhoneNumber`, `OtpService` (хеш кода, 5 мин, 5 попыток), `SessionService` (access 30 мин, refresh 60 дней с ротацией), `SmsSender` (log / sms.ru) |
| `src/Orders` | статусы и переходы, оформление с `Idempotency-Key`, заявки без корзины, уведомление менеджеров |
| `src/Orders/Composition` | состав заказа: `OrderCompositionSource` ← «Программа КП» (`KpCompositionSource` + `HttpKpClient`, заглушка) → менеджер (`ManagerCompositionSource`) → корзина (`CartCompositionSource`); `CompositionNormalizer` считает суммы |
| `src/Orders/Vehicle` | машина на карте: токен водителя, `VehicleFixFilter` (антиподмена), `VehicleLocationSource` ← телефон водителя / GPS-трекер (`StubTrackerClient`: Wialon, Traccar) |
| `src/Orders/Feedback` | отзыв (после «Завершён», правка 7 дней), претензии (`submitted → accepted/rejected → resolved`) |
| `src/Orders/Documents` | `OrderDocumentsSource`: менеджер (ссылки https), CRM (`CrmDocumentsSource`), Вызов Чат |
| `src/Loyalty` | скидка постоянного клиента: уровни `LoyaltyTiers`, `LoyaltyService` (quote, оформление, ЛК) |
| `src/Integrations` | `VyzovChatGateway` (+ `StubVyzovChatGateway`), `IntegrationNotReady` |
| `src/Push` | push-токены устройств; `PushSender` (сейчас лог, см. ниже) |
| `migrations/{mysql,sqlite}` | собственные таблицы `app_*` (таблицы CMS не трогаются) |
| `public/manager/` | веб-панель менеджера: заявки и смена статусов |

## Заказы и личный кабинет

Статусы: `processing → confirmed → preparing → delivering → in_progress → completed` (+ `cancelled`),
двигает менеджер (`PATCH /v1/manager/orders/{id}`), клиент получает push.

| Клиент (Bearer) | |
|---|---|
| `GET /v1/orders`, `GET /v1/orders/{id}` | заказ: + `subtotal`/`discount`, `tracking`, `review`/`canReview`, `claims`/`canClaim` |
| `GET /v1/orders/{id}/composition` | состав по разделам (КП → менеджер → корзина; `source: none`, если нет) |
| `GET /v1/orders/{id}/vehicle` | машина: `{status: enRoute/arrived/unknown, lat, lng, accuracy, heading, updatedAt, eta}`, только «В пути», иначе 409 |
| `POST /v1/orders/{id}/review` | `{rating 1–5, text}`: 201 создан / 200 изменён; 409 `review_unavailable`, `review_locked` |
| `GET/POST /v1/orders/{id}/claims` | претензия `{category, description, contactPreference, photos[]}`; 409 `claim_unavailable`, `claim_limit` |
| `GET /v1/orders/{id}/documents` | документы `{id, title, kind, source, date, url, size, mime}` |
| `GET /v1/me/loyalty` | скидка: `{percent, tier, spent, nextTier, tiers, override}` |
| `POST /v1/cart/quote` | токен необязателен; со входом — `subtotal` + `discount` |

| Менеджер (MANAGER_PHONES) | |
|---|---|
| `PUT/DELETE /v1/manager/orders/{id}/composition` | приложить/убрать состав (JSON из «Программы КП», версия растёт) |
| `POST /v1/manager/orders/{id}/documents`, `DELETE …/documents/m-{n}` | ссылки на документы (только https) |
| `POST /v1/manager/orders/{id}/driver` | назначить машину, токен водителя (показывается один раз, 48 ч) |
| `PUT /v1/manager/orders/{id}/links` | `{crmDealId, vyzovchatEventId}` — связи для интеграций |
| `GET /v1/manager/claims`, `PATCH /v1/manager/claims/{id}` | принять (клиенту — ссылка на чат «Жалобы»), решить, отклонить |
| `GET/PUT /v1/manager/users/{id}/loyalty` | персональная скидка `{percent \| null, note}` |

Водитель: `POST /v1/driver/orders/{id}/location` с `Authorization: Bearer <токен водителя>`,
`{lat, lng, accuracy, heading?, recordedAt?, etaMinutes?, arrived?}` → `{accepted, reason?}`. Точки отсеиваются:
точность хуже 500 м, скачок быстрее 150 км/ч (с учётом радиусов точности), вне Москвы и области
(`VEHICLE_REGION_BBOX`), у известных точек GPS-подмены (`VEHICLE_SPOOF_POINTS`, по умолчанию Внуково),
время из будущего / раньше последней точки. Хранится последняя достоверная точка; старше
`VEHICLE_STALE_SECONDS` (600) — клиент видит `status: unknown`.

### Интеграции (по умолчанию выключены)

| Переменные | Адаптер | Что нужно для боевого режима |
|---|---|---|
| `KP_SOURCE_ENABLED`, `KP_API_URL`, `KP_API_TOKEN` | `HttpKpClient` (заглушка) | формат «Программы КП»: HTTP-запрос по номеру сделки + маппинг в `CompositionInput` (см. docblock). Пока — состав присылает менеджер (`PUT …/composition`) |
| `VEHICLE_TRACKER` (`none`/`traccar`/`wialon`), `TRACKER_API_URL`, `TRACKER_API_TOKEN` | `StubTrackerClient` | реализовать запрос позиции (Traccar `/api/positions`, Wialon `core/search_item`); устройство машины — `trackerDeviceId` при назначении |
| `VYZOVCHAT_BASE_URL` (`https://vyzovchat.ru`), `VYZOVCHAT_ENABLED`, `VYZOVCHAT_API_TOKEN` | `StubVyzovChatGateway` | сервисный токен в Вызов Чате; приглашение `POST /api/events/{id}/invite` → `/join/<token>` (+ `vyzovchat://join/<token>`), отзыв в опрос `/api/events/{id}/review`, документы `/api/events/{id}/documents`. Сейчас ссылка чата — `VYZOVCHAT_BASE_URL` или `chatUrl` от менеджера |
| `CRM_DOCUMENTS_ENABLED`, `CRM_ACT_URL_TEMPLATE` | `CrmDocumentsSource` | шаблон ссылки на акт сделки (`<ORDERID>`), открывающейся клиенту без входа в CRM; позже — список файлов сделки из API CRM |
| `LOYALTY_ENABLED`, `LOYALTY_TIERS` / `LOYALTY_TIERS_FILE` | `LoyaltyTiers` | JSON `[[порог, %], …]` или `[{"threshold","percent"}]`; ошибка формата — отказ старта |

Включённая, но не реализованная интеграция бросает `IntegrationNotReady`: она пишется в лог,
клиент получает запасной вариант (состав из корзины, общий адрес чата, документы менеджера).

## Развёртывание на сервере сайта

1. Залить `api/` (без `var/`, `tests/`) в отдельную папку вне веб-корня сайта; веб-корень API — только `public/`,
   все запросы — на `public/index.php`; смонтировать как `https://<домен>/<путь-API>/` (`API_BASE_PATH=/<путь-API>`).
2. `.env`: `APP_ENV=production`, `DB_DSN=mysql:host=…;dbname=<база сайта>;charset=utf8mb4`, пользователь БД с правами
   на создание таблиц `app_*` (для чтения каталога — только SELECT на таблицы CMS), `AUTH_PEPPER` (64 случайных символа),
   `SMS_PROVIDER=smsru` + `SMSRU_API_ID`, `MANAGER_PHONES`, `ORDER_NOTIFY_EMAILS`.
3. `php bin/migrate.php`.
4. `var/` должен быть доступен на запись (логи); наружу не отдаётся.

## Что нужно от заказчика, чтобы закрыть оставшееся

| Что | Зачем |
|---|---|
| Схема БД сайта (`mysqldump --no-data`) + по 20–50 строк основных таблиц | `MysqlCatalogRepository` — каталог напрямую из БД со всеми связями вместо снапшота |
| Ключ sms.ru (или другой SMS-шлюз) | реальная отправка кодов входа |
| Ключи APNs (.p8, Key ID, Team ID) и Firebase (service account) | push о смене статуса заказа |
| Решение по CRM/почте | куда, кроме почты, дублировать заявки |
| Решение по поиску | подключать ли внешний поисковый сервис сайта вместо встроенного поиска |
