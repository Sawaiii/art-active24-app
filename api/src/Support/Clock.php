<?php

declare(strict_types=1);

namespace App\Support;

/**
 * Источник текущего времени (UTC) — подменяется в тестах.
 */
interface Clock
{
    public function now(): \DateTimeImmutable;
}
