<?php

declare(strict_types=1);

namespace App\Orders\Feedback;

use App\Http\HttpError;
use App\Integrations\VyzovChat\VyzovChatGateway;
use App\Orders\OrderStatus;
use App\Orders\OrderWindows;
use App\Support\Clock;
use App\Support\Logger;

/**
 * Оценка мероприятия: после «Завершён», один отзыв на заказ, правка — 7 дней.
 * Копия уходит в опрос мероприятия Вызов Чата (лучшим усилием).
 */
final class ReviewService
{
    public function __construct(
        private readonly FeedbackRepository $feedback,
        private readonly VyzovChatGateway $vyzovChat,
        private readonly Clock $clock,
        private readonly Logger $logger,
    ) {
    }

    /**
     * @param array<string, mixed> $order Order (доступ уже проверен) + vyzovchatEventId
     * @param array<string, mixed> $body ReviewInput
     * @return array{review: array<string, mixed>, created: bool}
     */
    public function submit(array $order, int $userId, array $body): array
    {
        $status = OrderStatus::from((string) $order['status']);
        if ((int) $order['userId'] !== $userId) {
            throw HttpError::forbidden();
        }
        if (!OrderWindows::canCreateReview($status)) {
            throw new HttpError(409, 'review_unavailable', 'Оценить мероприятие можно после завершения заказа');
        }
        $rating = $body['rating'] ?? null;
        if (!is_int($rating) || $rating < 1 || $rating > 5) {
            throw HttpError::validation(['rating' => 'Оценка от 1 до 5']);
        }
        $text = $body['text'] ?? null;
        if ($text !== null && (!is_string($text) || mb_strlen(trim($text)) > 2000)) {
            throw HttpError::validation(['text' => 'Не больше 2000 символов']);
        }
        $text = is_string($text) && trim($text) !== '' ? trim($text) : null;

        $orderId = (int) $order['id'];
        $existing = $this->feedback->review($orderId);
        $now = $this->clock->now();
        if ($existing !== null) {
            $createdAt = new \DateTimeImmutable((string) $existing['created_at'], new \DateTimeZone('UTC'));
            if (!OrderWindows::canReview($status, $createdAt, $now)) {
                throw new HttpError(409, 'review_locked', 'Отзыв можно изменить в течение ' . OrderWindows::REVIEW_EDIT_DAYS . ' дней');
            }
        }
        $created = $this->feedback->saveReview($orderId, $userId, $rating, $text);
        try {
            $this->vyzovChat->forwardReview($order, ['rating' => $rating, 'text' => $text]);
            if (!empty($order['vyzovchatEventId'])) {
                $this->feedback->markReviewForwarded($orderId);
            }
        } catch (\Throwable $e) {
            $this->logger->error('Отзыв не передан в Вызов Чат', ['order' => $orderId, 'message' => $e->getMessage()]);
        }
        $row = $this->feedback->review($orderId) ?? throw new \LogicException('Отзыв не сохранён');
        return ['review' => FeedbackPresenter::review($row, $status, $now), 'created' => $created];
    }
}
