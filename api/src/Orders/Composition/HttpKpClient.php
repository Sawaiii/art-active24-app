<?php

declare(strict_types=1);

namespace App\Orders\Composition;

use App\Integrations\IntegrationNotReady;

/**
 * Заглушка клиента «Программы КП» (KP_SOURCE_ENABLED=true + KP_API_URL + KP_API_TOKEN).
 * Выключено (по умолчанию) — КП нет, клиент видит состав от менеджера или из корзины.
 *
 * Что сделать, когда придёт формат:
 *  1. GET {KP_API_URL}/…/{dealId} с `Authorization: Bearer {KP_API_TOKEN}`, таймаут 5 с;
 *  2. разложить позиции по разделам (тип позиции → «Мебель», «Кейтеринг», «Персонал», «Логистика»),
 *     цены — в целые рубли; скидки КП → discounts (kind promo/manual), доставка → delivery;
 *  3. вернуть массив формы CompositionInput (+ 'revision' — номер версии КП, 'updatedAt' — ISO);
 *  4. кэшировать ответ на 5–10 минут (клиент открывает вкладку «Состав» часто).
 */
final class HttpKpClient implements KpClient
{
    public function __construct(
        private readonly bool $enabled,
        private readonly ?string $baseUrl,
        private readonly ?string $token,
    ) {
    }

    public function isEnabled(): bool
    {
        return $this->enabled && $this->baseUrl !== null && $this->token !== null;
    }

    public function proposal(string $dealId): ?array
    {
        if (!$this->isEnabled()) {
            return null;
        }
        throw IntegrationNotReady::for('Программа КП', "КП сделки {$dealId} (формат ещё не согласован)");
    }
}
