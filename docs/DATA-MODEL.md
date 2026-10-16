# Модель данных приложения

Источник истины — `contract/openapi.yaml`. Здесь — как шаблоны сайта ложатся на модель
и почему она устроена именно так.

## Шаблоны сайта → `Product.template` и `Product.orderMode`

| ID | Шаблон сайта | `template` | `orderMode` | Экран в приложении |
|---|---|---|---|---|
| 128 | Карточка товара 2026 | `configurator` | `cart` | конфигуратор: комплекты → варианты → время → допы → кол-во, липкий бар цены |
| 88 | Карточка товара простая | `simple` | `toggle` | список комплектов (состав, цена+единица), переключатель «в корзину» на комплект, допы |
| 81 | Карточка товара сложная | `showcase` | `toggle` | промо-шапка, «что это», видео, «было круто», комплекты (в комплекте / требования), группы допов |
| 123 | Сложная (персонал) | `staff` | `request` | лид, ставка «от 1 000 ₽ / час», галерея, похожий персонал, кнопка «Заказать» |
| 118 | Тимбилдинг 2.0 | `program` | `request` | контент-блоки: инфо-чипы, описание, навыки, этапы, фишки, тарифы, галерея |
| 119 | Площадка агрегатор | — (`Venue`) | `request` | отдельная сущность: агрегатор с фасетами, карточка площадки, заявка на расчёт |

Шаблон 128 дополнительно имеет `configuratorMode`:
`standard` (мебель, аттракционы, еда со станциями), `trampoline` (способ установки с фикс-надбавкой,
аренда+покупка, обязательные допы), `cateringMenu` (меню строк со своими счётчиками, одна позиция на
комплект, промо-награда), `masterclass` (пакеты + площадки + «как проходит / что включено»).
Режимы `tents`/`typography` есть в JS сайта, но на живых карточках не встречены — поддерживаются
моделью (`Sub.buyAbsolute`, `Complect.constructions`), экраны добавляются при появлении данных.

## Сущности

```
Category ─┬─ parent (дерево разделов сайта; id = id раздела CMS)
          └─ kind: catalog | buy | venues | landing | scenario

Product ──┬─ categories (основной раздел + дополнительные)
          ├─ media[]           фото/видео
          ├─ specs[]           характеристики
          ├─ complects[] ──┬─ rent / buy : PriceSide   (цена, лейбл, постфикс, «от», «по запросу», мин.кол-во, шаг %)
          │                ├─ time : TimeRule          (hours|days, default, percent)
          │                ├─ subs[] : Sub             (варианты: своя прибавка rent/buy, фикс-надбавка, фото/текст)
          │                ├─ menu[] : MenuRow         (cateringMenu: строки с кол-вом)
          │                ├─ includes[], requirements[] (шаблоны 81/88)
          │                └─ basePrice                (фикс за выезд, один раз)
          ├─ extras[] : Extra  (id стабильный, группа, обязательность) — «Доп. опции» и «Также подходит»
          ├─ similar[] : ProductSummary
          ├─ variantLinks[]    (комплект × вариант × rent|buy → slug, title)
          ├─ masterclass?      (метки, бейдж, площадки, шаги, «что включено», похожие, теги)
          └─ blocks[]          (showcase/staff/program: типизированные контент-блоки)

Venue ── photos[], type, address, metro[], area, capacity, priceFrom/unit, minHours, geo, description, howToRent

User ── orders[] ── items[] (снимок цены и названий) ── statusLog[]
     └─ favorites[], addresses[], devices[]
```

## Цена — одна формула, три реализации

Сервер (`api/src/Pricing/PriceCalculator.php`) — источник истины: корзина и заказ всегда
пересчитываются на сервере, клиентские цены игнорируются. Клиенты (`Pricing.swift`, `Pricing.kt`)
считают то же самое для мгновенного предпросмотра. Совпадение гарантирует общий набор примеров
`contract/pricing-vectors.json`, который прогоняют тесты всех трёх реализаций.

```
mult(hours, h)  = 1 + (h − def)·pct/100                         h ∈ [def..8]
mult(hours, Nд) = (1 + (8 − def)·pct/100) · (1 + 0.30·(N − 1))  N ≥ 2
mult(days, d)   = 1 + (d − def)·pct/100                         d ≥ def
side.sale = true → время не применяется (mult = 1)

unit   = (complect.side + sub.side) · mult + sub.flatSurcharge
extras = Σ выбранных допов (один раз на позицию, не × кол-во и не × время)
total  = step > 0 : unit·min + unit·step/100·max(0, qty − min) + extras + basePrice
         иначе    : unit·max(qty, min) + extras + basePrice
cateringMenu: total = Σ(row.qty·row.price) + basePrice + Σ(extra.qty·extra.price) − reward
onRequest (любая сторона «по запросу») → цена не считается, позиция помечается «по запросу»
```
Деньги — целые рубли (`int`). Округление — половина вверх: `floor(x + 0.5 + 1e-9)` (эпсилон гасит ошибку
double, напр. 64000 × 1.11719). Применяется к `unit` после умножения на множитель времени и к итогу со
ступенчатой скидкой. Одинаково в PHP, Kotlin, Swift.
Обязательные допы (`Extra.required`) входят в расчёт всегда, даже если клиент их не прислал.
Строка меню с `qty > 0` не может быть меньше `MenuRow.minQty`. Сумма позиции ≤ 1 000 000 000 ₽.
Строка-опция (шаблоны simple/showcase, orderMode=toggle): без `complectId`, только допы — цена = Σ допов × qty, обязательные допы не добавляются (на сайте это add-cart с item_type=option).
Награда `every_nth` в данных сайта не встречена — до получения схемы БД считается как «без награды».

API не отдаёт `null`: ключ с пустым значением опускается. Все поля, не перечисленные в `required`
схемы контракта, клиенты обязаны считать необязательными.

## Связь с БД сайта

Пока доступа к БД нет, `SnapshotCatalogRepository` отдаёт ту же модель из снапшота
(`tools/snapshot`). Когда появится схема — `MysqlCatalogRepository` собирает модель напрямую из таблиц
каталога CMS со всеми связями. Маппинг полей CMS → модель ведётся во внутренней документации.

## Свои таблицы приложения
`app_users`, `app_auth_codes`, `app_sessions`, `app_orders`, `app_order_items`, `app_order_status_log`,
`app_favorites`, `app_carts`, `app_devices` — `api/migrations/{mysql,sqlite}/`.
