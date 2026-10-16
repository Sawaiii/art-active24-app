<?php

declare(strict_types=1);

namespace App\Orders;

use App\Auth\PhoneNumber;
use App\Cart\CartRepository;
use App\Cart\QuoteService;
use App\Catalog\CatalogRepository;
use App\Catalog\VenueRepository;
use App\Db\Database;
use App\Http\HttpError;
use App\Pricing\CartItem;
use App\Pricing\PriceCalculator;
use App\Push\PushSender;
use App\Support\Clock;
use App\Support\Logger;
use App\Support\RateLimiter;

/**
 * Заявки: оформление корзины, заявки без корзины, отмена клиентом, смена статуса менеджером.
 */
final class OrderService
{
    private const TIMEZONE = 'Europe/Moscow';
    private const ORDERS_PER_HOUR = 10;
    private const REQUEST_KINDS = ['product', 'venue', 'callback'];

    public function __construct(
        private readonly OrderRepository $orders,
        private readonly OrderPresenter $presenter,
        private readonly QuoteService $quotes,
        private readonly CartRepository $carts,
        private readonly CatalogRepository $catalog,
        private readonly VenueRepository $venues,
        private readonly OrderNotifier $notifier,
        private readonly PushSender $push,
        private readonly RateLimiter $limiter,
        private readonly Logger $logger,
        private readonly Clock $clock,
    ) {
    }

    /**
     * @param array<string, mixed> $user
     * @param array<string, mixed> $body CheckoutRequest
     * @return array<string, mixed> Order
     */
    public function checkout(array $user, array $body, string $idempotencyKey): array
    {
        $existing = $this->existing($user, $idempotencyKey, ['cart']);
        if ($existing !== null) {
            return $existing;
        }
        $items = $this->items($body['items'] ?? null);
        [$eventDate, $eventDateTo] = $this->eventDates($body, required: true);
        $delivery = $this->delivery($body['delivery'] ?? null);
        $contact = $this->contact($user, $body);
        $this->limiter->hit('orders:user:' . $user['id'], self::ORDERS_PER_HOUR, 3600);

        $quote = $this->quotes->quote($items);
        $unavailable = array_filter($quote['lines'], static fn (array $l) => !$l['available']);
        if ($unavailable !== []) {
            $first = reset($unavailable);
            throw new HttpError(409, 'cart_changed', "«{$first['productName']}»: {$first['warning']}. Обновите корзину");
        }

        $id = $this->create($user, $idempotencyKey, [
            'kind' => 'cart',
            'event_date' => $eventDate,
            'event_date_to' => $eventDateTo,
            'delivery_method' => $delivery['method'],
            'delivery_address' => $delivery['address'],
            'contact_name' => $contact['name'],
            'contact_phone' => $contact['phone'],
            'comment' => $this->text($body['comment'] ?? null, 2000, 'comment'),
            'subject' => null,
            'details_json' => null,
            'total' => min($quote['total'], PriceCalculator::MAX_TOTAL),
            'has_on_request' => $quote['hasOnRequest'] ? 1 : 0,
        ], $quote['lines'], 'Заявка принята. Менеджер свяжется с вами для подтверждения');

        $this->carts->clear((int) $user['id']);
        return $this->afterCreate($id);
    }

    /**
     * @param array<string, mixed> $user
     * @param array<string, mixed> $body RequestCreate
     * @return array<string, mixed> Order
     */
    public function createRequest(array $user, array $body, string $idempotencyKey): array
    {
        $existing = $this->existing($user, $idempotencyKey, self::REQUEST_KINDS);
        if ($existing !== null) {
            return $existing;
        }
        $kind = $body['kind'] ?? null;
        [$subject, $details] = match ($kind) {
            'product' => $this->productRequest($body),
            'venue' => $this->venueRequest($body),
            'callback' => ['Обратный звонок', []],
            default => throw HttpError::validation(['kind' => 'Неизвестный тип заявки']),
        };
        [$eventDate] = $this->eventDates($body, required: $kind === 'venue');
        $contact = $this->contact($user, $body);
        $guests = $body['guests'] ?? null;
        if ($guests !== null && (!is_int($guests) || $guests < 1 || $guests > 100000)) {
            throw HttpError::validation(['guests' => 'Укажите количество гостей числом']);
        }
        $details += array_filter([
            'eventType' => $this->text($body['eventType'] ?? null, 100, 'eventType'),
            'guests' => $guests,
        ], static fn ($v) => $v !== null);
        $this->limiter->hit('orders:user:' . $user['id'], self::ORDERS_PER_HOUR, 3600);

        $id = $this->create($user, $idempotencyKey, [
            'kind' => (string) $kind,
            'event_date' => $eventDate,
            'event_date_to' => null,
            'delivery_method' => null,
            'delivery_address' => null,
            'contact_name' => $contact['name'],
            'contact_phone' => $contact['phone'],
            'comment' => $this->text($body['comment'] ?? null, 2000, 'comment'),
            'subject' => mb_substr($subject, 0, 300),
            'details_json' => $details === [] ? null : json_encode($details, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
            'total' => 0,
            'has_on_request' => 0,
        ], [], 'Заявка принята. Менеджер свяжется с вами');

        return $this->afterCreate($id);
    }

    /**
     * @param array<string, mixed> $user
     * @return array<string, mixed>
     */
    public function get(array $user, int $id): array
    {
        $row = $this->orders->row($id);
        if ($row === null || ((int) $row['user_id'] !== (int) $user['id'] && $user['role'] !== 'manager')) {
            throw HttpError::notFound('Заказ');
        }
        return $this->presenter->present($id) ?? throw HttpError::notFound('Заказ');
    }

    /**
     * @param array<string, mixed> $user
     * @return array{items: list<array<string, mixed>>, total: int}
     */
    public function listForUser(array $user, int $page, int $limit): array
    {
        $result = $this->orders->idsForUser((int) $user['id'], ($page - 1) * $limit, $limit);
        return ['items' => $this->presenter->presentMany($result['ids']), 'total' => $result['total']];
    }

    /** @return array{items: list<array<string, mixed>>, total: int} */
    public function listForManager(?OrderStatus $status, ?string $search, int $page, int $limit): array
    {
        $search = $search === null || trim($search) === '' ? null : trim($search);
        if ($search !== null && mb_strlen($search) > 50) {
            throw HttpError::validation(['q' => 'Не больше 50 символов']);
        }
        $result = $this->orders->idsForManager($status, $search, ($page - 1) * $limit, $limit);
        return ['items' => $this->presenter->presentMany($result['ids']), 'total' => $result['total']];
    }

    /**
     * Отмена клиентом — только своей заявки и только пока она «В обработке».
     *
     * @param array<string, mixed> $user
     * @return array<string, mixed>
     */
    public function cancel(array $user, int $id): array
    {
        $row = $this->orders->row($id);
        if ($row === null || (int) $row['user_id'] !== (int) $user['id']) {
            throw HttpError::notFound('Заказ');
        }
        $cannot = new HttpError(409, 'cannot_cancel', 'Заявку уже взяли в работу — для отмены свяжитесь с менеджером');
        if (!OrderStatus::from((string) $row['status'])->customerCanCancel()) {
            throw $cannot;
        }
        if (!$this->orders->changeStatus($id, OrderStatus::Processing, OrderStatus::Cancelled, 'Отменена клиентом', (int) $user['id'], null)) {
            throw $cannot;
        }
        $order = $this->presenter->present($id) ?? throw HttpError::notFound('Заказ');
        $this->bestEffort('orderCancelled', fn () => $this->notifier->orderCancelled($order));
        return $order;
    }

    /**
     * @param array<string, mixed> $manager
     * @param array<string, mixed> $body
     * @return array<string, mixed>
     */
    public function managerUpdate(array $manager, int $id, array $body): array
    {
        $row = $this->orders->row($id) ?? throw HttpError::notFound('Заказ');
        $next = OrderStatus::tryFrom((string) ($body['status'] ?? '')) ?? throw HttpError::validation(['status' => 'Неизвестный статус']);
        $current = OrderStatus::from((string) $row['status']);
        $invalid = new HttpError(409, 'invalid_transition', "Нельзя перевести из «{$current->label()}» в «{$next->label()}»");
        if (!$current->canMoveTo($next)) {
            throw $invalid;
        }
        $total = $body['total'] ?? null;
        if ($total !== null && (!is_int($total) || $total < 0 || $total > PriceCalculator::MAX_TOTAL)) {
            throw HttpError::validation(['total' => 'Итог — целое число рублей до 1 000 000 000']);
        }
        $comment = $this->text($body['comment'] ?? null, 1000, 'comment');

        if (!$this->orders->changeStatus($id, $current, $next, $comment, (int) $manager['id'], $total)) {
            throw new HttpError(409, 'invalid_transition', 'Статус заявки только что изменили — обновите карточку');
        }
        $order = $this->presenter->present($id) ?? throw HttpError::notFound('Заказ');
        $this->bestEffort('push', fn () => $this->push->sendToUser(
            (int) $row['user_id'],
            "Заявка {$order['number']}: {$next->label()}",
            $comment ?? 'Статус вашей заявки изменился',
            ['type' => 'order', 'orderId' => (string) $id],
        ));
        return $order;
    }

    /**
     * Повтор запроса с тем же Idempotency-Key возвращает ранее созданную заявку того же типа.
     *
     * @param array<string, mixed> $user
     * @param list<string> $kinds
     * @return array<string, mixed>|null
     */
    private function existing(array $user, string $key, array $kinds): ?array
    {
        $found = $this->orders->findByIdempotencyKey((int) $user['id'], $key);
        if ($found === null) {
            return null;
        }
        if (!in_array($found['kind'], $kinds, true)) {
            throw new HttpError(422, 'idempotency_key_reused', 'Ключ Idempotency-Key уже использован для другой заявки');
        }
        return $this->presenter->present($found['id']);
    }

    /**
     * @param array<string, mixed> $user
     * @param array<string, mixed> $columns
     * @param list<array<string, mixed>> $lines
     */
    private function create(array $user, string $key, array $columns, array $lines, string $historyComment): int
    {
        try {
            return $this->orders->create(
                ['user_id' => (int) $user['id'], 'idempotency_key' => $key] + $columns,
                $lines,
                $historyComment,
            );
        } catch (\PDOException $e) {
            // Параллельный запрос с тем же ключом успел первым — отдаём его заявку, а не 500.
            $found = Database::isUniqueViolation($e) ? $this->orders->findByIdempotencyKey((int) $user['id'], $key) : null;
            if ($found === null) {
                throw $e;
            }
            return $found['id'];
        }
    }

    /** @return array<string, mixed> */
    private function afterCreate(int $id): array
    {
        $order = $this->presenter->present($id) ?? throw new \LogicException('Заявка не создана');
        $this->bestEffort('orderCreated', fn () => $this->notifier->orderCreated($order));
        return $order;
    }

    /** Побочное действие после записи: его сбой логируется и не ломает ответ клиенту. */
    private function bestEffort(string $what, callable $action): void
    {
        try {
            $action();
        } catch (\Throwable $e) {
            $this->logger->error("Не выполнено: {$what}", ['exception' => $e::class, 'message' => $e->getMessage()]);
        }
    }

    /** @return list<CartItem> */
    private function items(mixed $raw): array
    {
        if (!is_array($raw) || !array_is_list($raw) || $raw === [] || count($raw) > 100) {
            throw HttpError::validation(['items' => 'Корзина пуста']);
        }
        return array_map(
            static fn (mixed $item, int $i) => CartItem::fromArray(is_array($item) ? $item : [], "items.{$i}."),
            $raw,
            array_keys($raw),
        );
    }

    /**
     * @param array<string, mixed> $body
     * @return array{0: ?string, 1: ?string}
     */
    private function eventDates(array $body, bool $required): array
    {
        $today = $this->clock->now()->setTimezone(new \DateTimeZone(self::TIMEZONE))->format('Y-m-d');
        $from = $this->date($body['eventDate'] ?? null, 'eventDate');
        $to = $this->date($body['eventDateTo'] ?? null, 'eventDateTo');
        if ($from === null) {
            if ($required) {
                throw HttpError::validation(['eventDate' => 'Укажите дату мероприятия']);
            }
            return [null, null];
        }
        if ($from < $today) {
            throw HttpError::validation(['eventDate' => 'Дата мероприятия уже прошла']);
        }
        if ($to !== null && $to < $from) {
            throw HttpError::validation(['eventDateTo' => 'Дата окончания раньше даты начала']);
        }
        return [$from, $to === $from ? null : $to];
    }

    private function date(mixed $value, string $field): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        $date = is_string($value) ? \DateTimeImmutable::createFromFormat('!Y-m-d', $value) : false;
        if ($date === false || $date->format('Y-m-d') !== $value) {
            throw HttpError::validation([$field => 'Дата в формате ГГГГ-ММ-ДД']);
        }
        return $value;
    }

    /** @return array{method: string, address: ?string} */
    private function delivery(mixed $raw): array
    {
        $method = is_array($raw) ? ($raw['method'] ?? null) : null;
        if (!in_array($method, ['delivery', 'pickup'], true)) {
            throw HttpError::validation(['delivery.method' => 'Выберите доставку или самовывоз']);
        }
        if ($method === 'pickup') {
            return ['method' => 'pickup', 'address' => null];
        }
        $address = $this->text($raw['address'] ?? null, 300, 'delivery.address');
        if ($address === null || mb_strlen($address) < 5) {
            throw HttpError::validation(['delivery.address' => 'Укажите адрес доставки']);
        }
        return ['method' => 'delivery', 'address' => $address];
    }

    /**
     * @param array<string, mixed> $user
     * @param array<string, mixed> $body
     * @return array{name: ?string, phone: string}
     */
    private function contact(array $user, array $body): array
    {
        $phone = isset($body['contactPhone']) && $body['contactPhone'] !== ''
            ? PhoneNumber::parse($body['contactPhone'], 'contactPhone', mobileOnly: false)->value
            : (string) $user['phone'];
        return [
            'name' => $this->text($body['contactName'] ?? null, 100, 'contactName') ?? $user['name'],
            'phone' => $phone,
        ];
    }

    /**
     * @param array<string, mixed> $body
     * @return array{0: string, 1: array<string, int>}
     */
    private function productRequest(array $body): array
    {
        $productId = $this->positiveId($body['productId'] ?? null, 'productId', required: true);
        $product = $this->catalog->product((int) $productId) ?? throw HttpError::validation(['productId' => 'Товар не найден']);
        $details = ['productId' => (int) $productId];
        $subject = (string) $product['name'];

        $complectId = $this->positiveId($body['complectId'] ?? null, 'complectId', required: false);
        if ($complectId !== null) {
            $complect = array_values(array_filter(
                $product['complects'] ?? [],
                static fn (array $c) => (int) $c['id'] === $complectId,
            ))[0] ?? throw HttpError::validation(['complectId' => 'Комплект не найден']);
            $subject .= ' — ' . $complect['title'];
            $details['complectId'] = $complectId;
        }
        return [$subject, $details];
    }

    /**
     * @param array<string, mixed> $body
     * @return array{0: string, 1: array<string, int>}
     */
    private function venueRequest(array $body): array
    {
        $venueId = (int) $this->positiveId($body['venueId'] ?? null, 'venueId', required: true);
        $venue = $this->venues->venue($venueId) ?? throw HttpError::validation(['venueId' => 'Площадка не найдена']);
        return ['Площадка: ' . $venue['name'], ['venueId' => $venueId]];
    }

    private function positiveId(mixed $value, string $field, bool $required): ?int
    {
        if ($value === null && !$required) {
            return null;
        }
        if (!is_int($value) || $value <= 0 || $value > 2_000_000_000) {
            throw HttpError::validation([$field => 'Ожидается числовой id']);
        }
        return $value;
    }

    private function text(mixed $value, int $max, string $field): ?string
    {
        if ($value === null) {
            return null;
        }
        if (!is_string($value)) {
            throw HttpError::validation([$field => 'Ожидается текст']);
        }
        $value = trim($value);
        if (mb_strlen($value) > $max) {
            throw HttpError::validation([$field => "Не больше {$max} символов"]);
        }
        return $value === '' ? null : $value;
    }
}
