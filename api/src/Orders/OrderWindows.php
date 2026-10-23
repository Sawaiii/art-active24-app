<?php

declare(strict_types=1);

namespace App\Orders;

/**
 * Сроки действий клиента по заказу: отзыв (после «Завершён», правка — 7 дней с момента отзыва)
 * и претензия (с «Мероприятие идёт» до 14 дней после «Завершён»).
 */
final class OrderWindows
{
    public const REVIEW_EDIT_DAYS = 7;
    public const CLAIM_DAYS_AFTER_COMPLETED = 14;

    public static function canCreateReview(OrderStatus $status): bool
    {
        return $status === OrderStatus::Completed;
    }

    public static function reviewEditableUntil(\DateTimeImmutable $reviewCreatedAt): \DateTimeImmutable
    {
        return $reviewCreatedAt->modify('+' . self::REVIEW_EDIT_DAYS . ' days');
    }

    /** Можно ли сейчас оставить или изменить отзыв. */
    public static function canReview(OrderStatus $status, ?\DateTimeImmutable $reviewCreatedAt, \DateTimeImmutable $now): bool
    {
        if (!self::canCreateReview($status)) {
            return false;
        }
        return $reviewCreatedAt === null || $now < self::reviewEditableUntil($reviewCreatedAt);
    }

    public static function canClaim(OrderStatus $status, ?\DateTimeImmutable $completedAt, \DateTimeImmutable $now): bool
    {
        if ($status === OrderStatus::InProgress) {
            return true;
        }
        if ($status !== OrderStatus::Completed || $completedAt === null) {
            return false;
        }
        return $now <= $completedAt->modify('+' . self::CLAIM_DAYS_AFTER_COMPLETED . ' days');
    }
}
