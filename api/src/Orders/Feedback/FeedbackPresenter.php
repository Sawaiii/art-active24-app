<?php

declare(strict_types=1);

namespace App\Orders\Feedback;

use App\Orders\OrderStatus;
use App\Orders\OrderWindows;
use App\Support\Time;

/**
 * OrderReview и OrderClaim в форме контракта.
 */
final class FeedbackPresenter
{
    public const CATEGORIES = [
        'late' => 'Опоздание',
        'quality' => 'Качество',
        'incomplete' => 'Комплектность',
        'staff' => 'Персонал',
        'other' => 'Другое',
    ];

    public const CLAIM_STATUSES = [
        'submitted' => 'Отправлена',
        'accepted' => 'Принята',
        'resolved' => 'Решена',
        'rejected' => 'Отклонена',
    ];

    public const CONTACT_PREFERENCES = ['call', 'messenger', 'email'];

    /**
     * @param array<string, mixed> $row app_order_reviews
     * @return array<string, mixed>
     */
    public static function review(array $row, OrderStatus $status, \DateTimeImmutable $now): array
    {
        $createdAt = new \DateTimeImmutable((string) $row['created_at'], new \DateTimeZone('UTC'));
        $until = OrderWindows::reviewEditableUntil($createdAt);
        return [
            'rating' => (int) $row['rating'],
            'text' => $row['text'],
            'createdAt' => Time::toApi((string) $row['created_at']),
            'updatedAt' => Time::toApi((string) $row['updated_at']),
            'editableUntil' => $until->format('Y-m-d\TH:i:s\Z'),
            'canEdit' => OrderWindows::canReview($status, $createdAt, $now),
        ];
    }

    /**
     * @param array<string, mixed> $row app_order_claims + order_number
     * @return array<string, mixed>
     */
    public static function claim(array $row): array
    {
        $photos = is_string($row['photos_json'] ?? null) ? json_decode((string) $row['photos_json'], true) : null;
        $status = (string) $row['status'];
        return [
            'id' => (int) $row['id'],
            'orderId' => (int) $row['order_id'],
            'orderNumber' => $row['order_number'] ?? null,
            'category' => (string) $row['category'],
            'categoryLabel' => self::CATEGORIES[$row['category']] ?? 'Другое',
            'description' => (string) $row['description'],
            'contactPreference' => (string) $row['contact_preference'],
            'photos' => is_array($photos) && $photos !== [] ? $photos : null,
            'status' => $status,
            'statusLabel' => self::CLAIM_STATUSES[$status] ?? $status,
            'managerComment' => $row['manager_comment'],
            'chatUrl' => $status === 'accepted' || $status === 'resolved' ? $row['chat_url'] : null,
            'chatAppUrl' => $status === 'accepted' || $status === 'resolved' ? $row['chat_app_url'] : null,
            'createdAt' => Time::toApi((string) $row['created_at']),
            'updatedAt' => Time::toApi((string) $row['updated_at']),
        ];
    }
}
