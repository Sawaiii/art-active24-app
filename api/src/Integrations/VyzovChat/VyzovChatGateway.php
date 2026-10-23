<?php

declare(strict_types=1);

namespace App\Integrations\VyzovChat;

/**
 * Вызов Чат (https://vyzovchat.ru) — чат мероприятий компании. Заказ связывается с мероприятием
 * менеджером (PUT /v1/manager/orders/{id}/links, vyzovchatEventId).
 */
interface VyzovChatGateway
{
    /**
     * Ссылка на чат «Жалобы» для клиента по принятой претензии.
     *
     * @param array<string, mixed> $order Order (форма контракта) + vyzovchatEventId
     * @param array<string, mixed> $claim OrderClaim
     * @return array{url: string, appUrl: ?string}
     */
    public function complaintChat(array $order, array $claim): array;

    /**
     * Передать оценку клиента в опрос мероприятия.
     *
     * @param array<string, mixed> $order
     * @param array{rating: int, text: ?string} $review
     */
    public function forwardReview(array $order, array $review): void;

    /**
     * Документы мероприятия (акты приёма/возврата, act_url сделки).
     *
     * @return list<array{title: string, kind: string, url: string, date?: ?string, size?: ?int, mime?: ?string}>
     */
    public function eventDocuments(int $eventId): array;
}
