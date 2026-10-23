<?php

declare(strict_types=1);

namespace App\Orders\Documents;

use App\Integrations\VyzovChat\VyzovChatGateway;

/**
 * Документы мероприятия в Вызов Чате (акты приёма/возврата, act_url) — через VyzovChatGateway.
 */
final class VyzovChatDocumentsSource implements OrderDocumentsSource
{
    public function __construct(private readonly VyzovChatGateway $gateway)
    {
    }

    public function documents(array $order): array
    {
        $eventId = $order['vyzovchatEventId'] ?? null;
        if (!is_int($eventId) || $eventId <= 0) {
            return [];
        }
        $out = [];
        foreach ($this->gateway->eventDocuments($eventId) as $i => $doc) {
            $out[] = [
                'id' => 'vc-' . ($i + 1),
                'title' => $doc['title'],
                'kind' => $doc['kind'],
                'source' => 'vyzovchat',
                'date' => $doc['date'] ?? null,
                'url' => $doc['url'],
                'size' => $doc['size'] ?? null,
                'mime' => $doc['mime'] ?? null,
            ];
        }
        return $out;
    }
}
