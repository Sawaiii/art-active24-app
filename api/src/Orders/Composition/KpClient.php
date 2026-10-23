<?php

declare(strict_types=1);

namespace App\Orders\Composition;

/**
 * Клиент «Программы КП» (CRM компании). Формат КП пришлют позже — реализация HTTP-клиента
 * и маппинг их полей в CompositionInput появятся тогда же (см. KpCompositionSource).
 */
interface KpClient
{
    /**
     * Актуальное КП по номеру сделки, уже приведённое к CompositionInput (+ updatedAt ISO, revision).
     *
     * @return array<string, mixed>|null null — КП по сделке нет
     */
    public function proposal(string $dealId): ?array;
}
