<?php

declare(strict_types=1);

namespace App\Support;

/**
 * Управляемые часы для тестов.
 */
final class FrozenClock implements Clock
{
    private \DateTimeImmutable $now;

    public function __construct(string $now = '2026-10-16 12:00:00')
    {
        $this->now = new \DateTimeImmutable($now, new \DateTimeZone('UTC'));
    }

    public function now(): \DateTimeImmutable
    {
        return $this->now;
    }

    public function advance(int $seconds): void
    {
        $this->now = $this->now->modify("+{$seconds} seconds");
    }
}
