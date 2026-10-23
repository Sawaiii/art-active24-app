<?php

declare(strict_types=1);

namespace App\Orders\Feedback;

use App\Http\HttpError;
use App\Integrations\VyzovChat\StubVyzovChatGateway;
use App\Integrations\VyzovChat\VyzovChatGateway;
use App\Orders\OrderRepository;
use App\Orders\OrderStatus;
use App\Orders\OrderWindows;
use App\Push\PushSender;
use App\Support\Clock;
use App\Support\Logger;
use App\Support\RateLimiter;

/**
 * Претензии «Что-то пошло не так?»: клиент отправляет (submitted), менеджер принимает (accepted —
 * клиенту ссылка на чат «Жалобы» в Вызов Чате) или отклоняет, затем решает (resolved).
 */
final class ClaimService
{
    public const MAX_OPEN = 3;
    private const PER_HOUR = 5;
    private const TRANSITIONS = [
        'submitted' => ['accepted', 'rejected'],
        'accepted' => ['resolved'],
    ];

    public function __construct(
        private readonly FeedbackRepository $feedback,
        private readonly OrderRepository $orders,
        private readonly VyzovChatGateway $vyzovChat,
        private readonly PushSender $push,
        private readonly RateLimiter $limiter,
        private readonly Clock $clock,
        private readonly Logger $logger,
        /** VYZOVCHAT_BASE_URL — если интеграция не дала ссылку. */
        private readonly string $chatFallbackUrl,
    ) {
    }

    /**
     * @param array<string, mixed> $order Order (доступ проверен)
     * @param array<string, mixed> $body ClaimInput
     * @return array<string, mixed> OrderClaim
     */
    public function create(array $order, int $userId, array $body): array
    {
        if ((int) $order['userId'] !== $userId) {
            throw HttpError::forbidden();
        }
        $orderId = (int) $order['id'];
        $status = OrderStatus::from((string) $order['status']);
        if (!OrderWindows::canClaim($status, $this->orders->completedAt($orderId), $this->clock->now())) {
            throw new HttpError(409, 'claim_unavailable', 'Претензию можно отправить с начала мероприятия и до '
                . OrderWindows::CLAIM_DAYS_AFTER_COMPLETED . ' дней после завершения — или напишите менеджеру');
        }
        $row = $this->validate($body);
        if ($this->feedback->countClaims($orderId, ['submitted', 'accepted']) >= self::MAX_OPEN) {
            throw new HttpError(409, 'claim_limit', 'По заказу уже есть открытые претензии — менеджер с ними работает');
        }
        $this->limiter->hit('claims:user:' . $userId, self::PER_HOUR, 3600);
        $id = $this->feedback->createClaim(['order_id' => $orderId, 'user_id' => $userId, 'status' => 'submitted'] + $row);
        $claim = FeedbackPresenter::claim($this->feedback->claim($id) ?? throw new \LogicException('Претензия не сохранена'));
        $this->logger->info('Новая претензия', ['order' => $order['number'], 'claim' => $id, 'category' => $row['category']]);
        return $claim;
    }

    /**
     * @param array<string, mixed> $order
     * @return list<array<string, mixed>>
     */
    public function forOrder(array $order): array
    {
        return array_map(FeedbackPresenter::claim(...), $this->feedback->claimsFor([(int) $order['id']])[(int) $order['id']] ?? []);
    }

    /** @return array{items: list<array<string, mixed>>, total: int} */
    public function listForManager(?string $status, int $page, int $limit): array
    {
        if ($status !== null && !isset(FeedbackPresenter::CLAIM_STATUSES[$status])) {
            throw HttpError::badRequest('invalid_status', 'Неизвестный статус претензии');
        }
        $result = $this->feedback->claimsForManager($status, ($page - 1) * $limit, $limit);
        return ['items' => array_map(FeedbackPresenter::claim(...), $result['items']), 'total' => $result['total']];
    }

    /**
     * @param array<string, mixed> $body {status, comment?, chatUrl?}
     * @return array<string, mixed> OrderClaim
     */
    public function managerUpdate(int $claimId, array $body): array
    {
        $row = $this->feedback->claim($claimId) ?? throw HttpError::notFound('Претензия');
        $from = (string) $row['status'];
        $to = $body['status'] ?? null;
        if (!is_string($to) || !in_array($to, self::TRANSITIONS[$from] ?? [], true)) {
            throw new HttpError(409, 'invalid_transition', 'Нельзя перевести претензию из «'
                . (FeedbackPresenter::CLAIM_STATUSES[$from] ?? $from) . '» в этот статус');
        }
        $comment = $body['comment'] ?? null;
        if ($comment !== null && (!is_string($comment) || mb_strlen(trim($comment)) > 1000)) {
            throw HttpError::validation(['comment' => 'Не больше 1000 символов']);
        }
        $fields = [];
        if (is_string($comment) && trim($comment) !== '') {
            $fields['manager_comment'] = trim($comment);
        }
        if ($to === 'accepted') {
            [$fields['chat_url'], $fields['chat_app_url']] = $this->chatLink($row, $body['chatUrl'] ?? null);
        }
        if (!$this->feedback->moveClaim($claimId, $from, $to, $fields)) {
            throw new HttpError(409, 'invalid_transition', 'Претензию только что изменили — обновите список');
        }
        $claim = FeedbackPresenter::claim($this->feedback->claim($claimId) ?? $row);
        $this->notify((int) $row['user_id'], $claim);
        return $claim;
    }

    /**
     * Ссылка на чат: явная от менеджера (https) или от интеграции Вызов Чата; сбой интеграции — общий адрес.
     *
     * @param array<string, mixed> $row
     * @return array{0: string, 1: ?string}
     */
    private function chatLink(array $row, mixed $explicit): array
    {
        if ($explicit !== null) {
            if (!is_string($explicit) || filter_var($explicit, FILTER_VALIDATE_URL) === false
                || strtolower((string) parse_url($explicit, PHP_URL_SCHEME)) !== 'https' || strlen($explicit) > 500) {
                throw HttpError::validation(['chatUrl' => 'Ссылка https:// до 500 символов']);
            }
            return [$explicit, StubVyzovChatGateway::appUrlFor($explicit)];
        }
        $order = ['id' => (int) $row['order_id'], 'number' => $row['order_number']] + $this->orders->links((int) $row['order_id']);
        try {
            $link = $this->vyzovChat->complaintChat($order, FeedbackPresenter::claim($row));
        } catch (\Throwable $e) {
            $this->logger->error('Чат «Жалобы» не создан в Вызов Чате', ['claim' => $row['id'], 'message' => $e->getMessage()]);
            $link = ['url' => rtrim($this->chatFallbackUrl, '/') . '/', 'appUrl' => null];
        }
        return [$link['url'], $link['appUrl'] ?? StubVyzovChatGateway::appUrlFor($link['url'])];
    }

    /** @param array<string, mixed> $claim */
    private function notify(int $userId, array $claim): void
    {
        $body = match ($claim['status']) {
            'accepted' => 'Претензию приняли — откройте чат с менеджером в Вызов Чате',
            'resolved' => 'Претензия решена',
            'rejected' => 'Претензию рассмотрели — подробности в заказе',
            default => 'Статус претензии изменился',
        };
        try {
            $this->push->sendToUser($userId, "Заказ {$claim['orderNumber']}", $claim['managerComment'] ?? $body, [
                'type' => 'order', 'orderId' => (string) $claim['orderId'],
            ]);
        } catch (\Throwable $e) {
            $this->logger->error('Не выполнено: push по претензии', ['message' => $e->getMessage()]);
        }
    }

    /**
     * @param array<string, mixed> $body
     * @return array<string, mixed> колонки претензии
     */
    private function validate(array $body): array
    {
        $errors = [];
        $category = $body['category'] ?? null;
        if (!is_string($category) || !isset(FeedbackPresenter::CATEGORIES[$category])) {
            $errors['category'] = 'Выберите, что пошло не так';
        }
        $description = is_string($body['description'] ?? null) ? trim($body['description']) : '';
        if (mb_strlen($description) < 10 || mb_strlen($description) > 2000) {
            $errors['description'] = 'Опишите ситуацию: от 10 до 2000 символов';
        }
        $contact = $body['contactPreference'] ?? 'call';
        if (!in_array($contact, FeedbackPresenter::CONTACT_PREFERENCES, true)) {
            $errors['contactPreference'] = 'Как связаться: call, messenger или email';
        }
        $photos = $body['photos'] ?? null;
        $urls = [];
        if ($photos !== null) {
            if (!is_array($photos) || !array_is_list($photos) || count($photos) > 10) {
                $errors['photos'] = 'До 10 фото';
            } else {
                foreach ($photos as $i => $photo) {
                    $url = is_array($photo) && is_string($photo['url'] ?? null) ? $photo['url'] : '';
                    if (filter_var($url, FILTER_VALIDATE_URL) === false || strtolower((string) parse_url($url, PHP_URL_SCHEME)) !== 'https' || strlen($url) > 1000) {
                        $errors["photos.{$i}.url"] = 'Ссылка https://';
                        continue;
                    }
                    $urls[] = ['url' => $url];
                }
            }
        }
        if ($errors !== []) {
            throw HttpError::validation($errors);
        }
        return [
            'category' => $category,
            'description' => $description,
            'contact_preference' => $contact,
            'photos_json' => $urls === [] ? null : json_encode($urls, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR),
        ];
    }
}
