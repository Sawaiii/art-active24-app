<?php

declare(strict_types=1);

namespace App\Orders;

/**
 * Статусы заявки. Создаётся в processing («В обработке»), дальше двигает менеджер.
 */
enum OrderStatus: string
{
    case Processing = 'processing';
    case Confirmed = 'confirmed';
    case Preparing = 'preparing';
    case Delivering = 'delivering';
    case InProgress = 'in_progress';
    case Completed = 'completed';
    case Cancelled = 'cancelled';

    public function label(): string
    {
        return match ($this) {
            self::Processing => 'В обработке',
            self::Confirmed => 'Подтверждён',
            self::Preparing => 'Комплектуется',
            self::Delivering => 'В пути',
            self::InProgress => 'Мероприятие идёт',
            self::Completed => 'Завершён',
            self::Cancelled => 'Отменён',
        };
    }

    /** @return list<self> */
    public function allowedNext(): array
    {
        return match ($this) {
            self::Processing => [self::Confirmed, self::Cancelled],
            self::Confirmed => [self::Preparing, self::Delivering, self::InProgress, self::Completed, self::Cancelled],
            self::Preparing => [self::Delivering, self::InProgress, self::Cancelled],
            self::Delivering => [self::InProgress, self::Completed, self::Cancelled],
            self::InProgress => [self::Completed],
            // Отменённую заявку менеджер может вернуть в работу (клиент передумал).
            self::Cancelled => [self::Processing],
            self::Completed => [],
        };
    }

    public function canMoveTo(self $next): bool
    {
        return in_array($next, $this->allowedNext(), true);
    }

    public function customerCanCancel(): bool
    {
        return $this === self::Processing;
    }
}
