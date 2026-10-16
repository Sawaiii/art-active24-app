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
| `src/Push` | push-токены устройств; `PushSender` (сейчас лог, см. ниже) |
| `migrations/{mysql,sqlite}` | собственные таблицы `app_*` (таблицы CMS не трогаются) |
| `public/manager/` | веб-панель менеджера: заявки и смена статусов |

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
