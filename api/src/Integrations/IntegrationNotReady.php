<?php

declare(strict_types=1);

namespace App\Integrations;

/**
 * Интеграция включена в конфигурации, но адаптер ещё не реализован (нет доступа / формата).
 * Вызывающий код ловит её как сбой внешней системы: логирует и работает на запасном варианте.
 */
final class IntegrationNotReady extends \RuntimeException
{
    public static function for(string $integration, string $what): self
    {
        return new self("Интеграция «{$integration}» включена, но адаптер не готов: {$what}");
    }
}
