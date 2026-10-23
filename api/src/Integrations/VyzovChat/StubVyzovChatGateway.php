<?php

declare(strict_types=1);

namespace App\Integrations\VyzovChat;

use App\Integrations\IntegrationNotReady;

/**
 * Адаптер Вызов Чата. Пока доступа к API нет — заглушка:
 *  - выключен (по умолчанию): чат претензии — общий адрес VYZOVCHAT_BASE_URL, отзыв и документы — пусто;
 *  - включён (VYZOVCHAT_ENABLED=true + VYZOVCHAT_API_TOKEN): бросает IntegrationNotReady,
 *    вызывающий код логирует и откатывается на поведение «выключен».
 *
 * Что сделать для боевого режима (API Вызов Чата, см. app/server/internal/server в его репозитории):
 *  - complaintChat: POST /api/events/{eventId}/invite {"role":"member"} → {"token","path":"/join/<token>"};
 *    клиенту — url = BASE + path, appUrl = "vyzovchat://join/<token>"; текст претензии — сообщением в
 *    служебный чат «Жалобы» ответственного (сейчас POST /api/events/{id}/complaints принимает жалобу
 *    только на участника мероприятия — нужен эндпоинт «жалоба клиента» или сервисный пользователь).
 *  - forwardReview: POST /api/events/{eventId}/review → {"token"}; затем POST /api/review/{token}
 *    с оценкой (у опроса 4 оценки: team/senior/equipment/manager — общую оценку кладём во все и
 *    текст в комментарий) — нужно согласовать с владельцами Вызов Чата.
 *  - eventDocuments: GET /api/events/{eventId}/documents (file_url — presigned, живёт недолго:
 *    отдавать клиенту через свой редирект) + act_url мероприятия (TONY_ACT_URL сделки).
 *  Авторизация: сервисный токен (VYZOVCHAT_API_TOKEN) — в Вызов Чате его пока нет, нужен по аналогии с CRM_TOKEN.
 */
final class StubVyzovChatGateway implements VyzovChatGateway
{
    public function __construct(
        private readonly string $baseUrl,
        private readonly bool $enabled,
    ) {
    }

    public function complaintChat(array $order, array $claim): array
    {
        if ($this->enabled && !empty($order['vyzovchatEventId'])) {
            throw IntegrationNotReady::for('Вызов Чат', 'приглашение в чат «Жалобы»');
        }
        return ['url' => rtrim($this->baseUrl, '/') . '/', 'appUrl' => null];
    }

    public function forwardReview(array $order, array $review): void
    {
        if ($this->enabled && !empty($order['vyzovchatEventId'])) {
            throw IntegrationNotReady::for('Вызов Чат', 'отзыв клиента в опрос мероприятия');
        }
    }

    public function eventDocuments(int $eventId): array
    {
        if ($this->enabled) {
            throw IntegrationNotReady::for('Вызов Чат', 'документы мероприятия');
        }
        return [];
    }

    /**
     * Ссылка приложения для https-приглашения вида https://vyzovchat.ru/join/<token>.
     */
    public static function appUrlFor(string $httpsUrl): ?string
    {
        $path = (string) parse_url($httpsUrl, PHP_URL_PATH);
        return preg_match('~^/join/([A-Za-z0-9_-]{8,128})/?$~', $path, $m) === 1 ? 'vyzovchat://join/' . $m[1] : null;
    }
}
