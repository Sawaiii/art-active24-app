<?php

declare(strict_types=1);

namespace App\Orders;

use App\Support\Time;

/**
 * Собирает Order (форма контракта) из строк БД. Списки — пачкой (OrderRepository::load).
 */
final class OrderPresenter
{
    public function __construct(private readonly OrderRepository $orders)
    {
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
        return array_map(
            fn (array $loaded) => $this->order($loaded['order'], $loaded['items'], $loaded['history']),
            $this->orders->load($ids),
        );
    }

    /**
     * @param array<string, mixed> $row
     * @param list<array<string, mixed>> $items
     * @param list<array<string, mixed>> $history
     * @return array<string, mixed>
     */
    private function order(array $row, array $items, array $history): array
    {
        $status = OrderStatus::from((string) $row['status']);
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
        ];
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
