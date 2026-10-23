<?php

declare(strict_types=1);

namespace App\Orders;

use App\Loyalty\LoyaltyService;
use App\Orders\Feedback\FeedbackPresenter;
use App\Orders\Feedback\FeedbackRepository;
use App\Support\Clock;
use App\Support\Time;

/**
 * Собирает Order (форма контракта) из строк БД. Списки — пачкой (OrderRepository::load + отзывы
 * и претензии одним запросом на страницу).
 */
final class OrderPresenter
{
    public function __construct(
        private readonly OrderRepository $orders,
        private readonly FeedbackRepository $feedback,
        private readonly Clock $clock,
    ) {
    }

    /** @return array<string, mixed>|null */
    public function present(int $orderId): ?array
    {
        return $this->presentMany([$orderId])[0] ?? null;
    }

    /**
     * @param list<int> $ids
     * @return list<array<string, mixed>>
     */
    public function presentMany(array $ids): array
    {
        $loaded = $this->orders->load($ids);
        $loadedIds = array_map(static fn (array $l) => (int) $l['order']['id'], $loaded);
        $reviews = $this->feedback->reviewsFor($loadedIds);
        $claims = $this->feedback->claimsFor($loadedIds);
        return array_map(
            fn (array $l) => $this->order(
                $l['order'],
                $l['items'],
                $l['history'],
                $reviews[(int) $l['order']['id']] ?? null,
                $claims[(int) $l['order']['id']] ?? [],
            ),
            $loaded,
        );
    }

    /**
     * @param array<string, mixed> $row
     * @param list<array<string, mixed>> $items
     * @param list<array<string, mixed>> $history
     * @param array<string, mixed>|null $review
     * @param list<array<string, mixed>> $claims
     * @return array<string, mixed>
     */
    private function order(array $row, array $items, array $history, ?array $review, array $claims): array
    {
        $status = OrderStatus::from((string) $row['status']);
        $now = $this->clock->now();
        $reviewCreatedAt = $review === null ? null : new \DateTimeImmutable((string) $review['created_at'], new \DateTimeZone('UTC'));
        $discountAmount = (int) ($row['discount_amount'] ?? 0);
        $discountPercent = (int) ($row['discount_percent'] ?? 0);
        return [
            'id' => (int) $row['id'],
            'number' => (string) $row['number'],
            'kind' => (string) $row['kind'],
            'status' => $status->value,
            'statusLabel' => $status->label(),
            'createdAt' => Time::toApi((string) $row['created_at']),
            'updatedAt' => Time::toApi((string) $row['updated_at']),
            'eventDate' => $row['event_date'],
            'eventDateTo' => $row['event_date_to'],
            'delivery' => $row['delivery_method'] === null ? null : [
                'method' => (string) $row['delivery_method'],
                'address' => $row['delivery_address'],
            ],
            'contactName' => $row['contact_name'],
            'contactPhone' => (string) $row['contact_phone'],
            'comment' => $row['comment'],
            'subject' => $row['subject'],
            'details' => $this->details($row['details_json'] ?? null),
            'lines' => array_map($this->line(...), $items),
            'subtotal' => $discountAmount > 0 ? (int) $row['subtotal'] : null,
            'discount' => $discountAmount > 0 ? [
                'kind' => LoyaltyService::KIND,
                'title' => LoyaltyService::title($discountPercent),
                'percent' => $discountPercent,
                'amount' => $discountAmount,
            ] : null,
            'total' => (int) $row['total'],
            'hasOnRequest' => (bool) $row['has_on_request'],
            'canCancel' => $status->customerCanCancel(),
            'history' => array_map(static function (array $event): array {
                $s = OrderStatus::from((string) $event['status']);
                return [
                    'status' => $s->value,
                    'label' => $s->label(),
                    'at' => Time::toApi((string) $event['created_at']),
                    'comment' => $event['comment'],
                ];
            }, $history),
            'userId' => (int) $row['user_id'],
            'tracking' => $status === OrderStatus::Delivering,
            'canReview' => OrderWindows::canReview($status, $reviewCreatedAt, $now),
            'review' => $review === null ? null : FeedbackPresenter::review($review, $status, $now),
            'canClaim' => OrderWindows::canClaim($status, $this->completedAt($history), $now),
            'claims' => $claims === [] ? null : array_map(FeedbackPresenter::claim(...), $claims),
        ];
    }

    /** @param list<array<string, mixed>> $history */
    private function completedAt(array $history): ?\DateTimeImmutable
    {
        $at = null;
        foreach ($history as $event) {
            if ($event['status'] === OrderStatus::Completed->value) {
                $at = (string) $event['created_at'];
            }
        }
        return $at === null ? null : new \DateTimeImmutable($at, new \DateTimeZone('UTC'));
    }

    /** @return array<string, int|string>|null eventType, guests, productId, complectId, venueId */
    private function details(mixed $json): ?array
    {
        $data = is_string($json) ? json_decode($json, true) : null;
        return is_array($data) && $data !== [] ? $data : null;
    }

    /**
     * @param array<string, mixed> $item
     * @return array<string, mixed>
     */
    private function line(array $item): array
    {
        return [
            'productId' => (int) $item['product_id'],
            'productName' => (string) $item['product_name'],
            'productSlug' => $item['product_slug'],
            'image' => $item['image'],
            'art' => $item['art'],
            'complectTitle' => $item['complect_title'],
            'subTitle' => $item['sub_title'],
            'timeLabel' => $item['time_label'],
            'qty' => (int) $item['qty'],
            'qtyUnit' => $item['qty_unit'],
            'extras' => json_decode((string) ($item['extras_json'] ?? '[]'), true) ?: [],
            'unitPrice' => (int) $item['unit_price'],
            'total' => (int) $item['total'],
            'onRequest' => (bool) $item['on_request'],
            'input' => json_decode((string) $item['input_json'], true),
        ];
    }
}
