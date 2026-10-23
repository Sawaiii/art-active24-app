<?php

declare(strict_types=1);

namespace App\Loyalty;

use App\Db\Database;
use App\Http\HttpError;
use App\Orders\OrderStatus;

/**
 * Скидка постоянного клиента: уровень по сумме всех завершённых заказов пользователя,
 * персональная скидка менеджера важнее уровня. Применяется к сумме позиций ПОСЛЕ расчёта строк —
 * цены строк (и эталонные векторы pricing-vectors.json) не меняются.
 */
final class LoyaltyService
{
    public const KIND = 'loyalty';

    public function __construct(
        private readonly Database $db,
        private readonly LoyaltyTiers $tiers,
        private readonly bool $enabled = true,
    ) {
    }

    /** Скидка в рублях: floor(subtotal × percent / 100 + 0.5) — половина копейки вверх, целые рубли. */
    public static function amount(int $subtotal, int $percent): int
    {
        if ($subtotal <= 0 || $percent <= 0) {
            return 0;
        }
        return intdiv($subtotal * $percent + 50, 100);
    }

    public static function title(int $percent): string
    {
        return "Скидка постоянного клиента −{$percent}%";
    }

    /** Действующий процент пользователя (0 — скидки нет или программа выключена). */
    public function percentFor(int $userId): int
    {
        if (!$this->enabled) {
            return 0;
        }
        $override = $this->override($userId);
        if ($override !== null) {
            return $override['percent'];
        }
        return $this->tiers->tier($this->tiers->indexFor($this->spent($userId)['spent']))['percent'];
    }

    /**
     * Скидка в quote: с ней появляются subtotal и discount, total уменьшается. Без скидки quote не меняется.
     *
     * @param array<string, mixed> $quote {lines, total, hasOnRequest, count}
     * @return array<string, mixed>
     */
    public function applyToQuote(array $quote, int $percent): array
    {
        $subtotal = (int) $quote['total'];
        $amount = self::amount($subtotal, $percent);
        if ($amount === 0) {
            return $quote;
        }
        return [
            'subtotal' => $subtotal,
            'discount' => ['kind' => self::KIND, 'title' => self::title($percent), 'percent' => $percent, 'amount' => $amount],
            'total' => $subtotal - $amount,
        ] + $quote;
    }

    /** @return array<string, mixed> Loyalty (форма контракта) */
    public function summary(int $userId): array
    {
        ['spent' => $spent, 'count' => $count] = $this->spent($userId);
        $index = $this->tiers->indexFor($spent);
        $tier = $this->tiers->tier($index);
        $override = $this->override($userId);
        $percent = !$this->enabled ? 0 : ($override['percent'] ?? $tier['percent']);

        $next = null;
        for ($i = $index + 1; $i < $this->tiers->count(); $i++) {
            $candidate = $this->tiers->tier($i);
            // Следующий уровень показываем, только если он больше действующей скидки.
            if ($candidate['percent'] > $percent) {
                $next = $candidate + ['remaining' => $candidate['threshold'] - $spent];
                break;
            }
        }
        return [
            'percent' => $percent,
            'source' => $override !== null ? 'override' : 'tier',
            'tier' => $tier,
            'spent' => $spent,
            'completedOrders' => $count,
            'nextTier' => $next,
            'tiers' => $this->tiers->all(),
            'override' => $override,
        ];
    }

    /**
     * Сводка для менеджера: 404, если пользователя нет.
     *
     * @return array<string, mixed> Loyalty
     */
    public function summaryForUser(int $userId): array
    {
        $this->assertUser($userId);
        return $this->summary($userId);
    }

    private function assertUser(int $userId): void
    {
        if ($this->db->scalar('SELECT id FROM app_users WHERE id = ?', [$userId]) === null) {
            throw HttpError::notFound('Пользователь');
        }
    }

    /**
     * Персональная скидка менеджера; null — снять.
     *
     * @return array<string, mixed> Loyalty
     */
    public function setOverride(int $userId, mixed $percent, mixed $note): array
    {
        $this->assertUser($userId);
        if ($percent !== null && (!is_int($percent) || $percent < 0 || $percent > LoyaltyTiers::MAX_PERCENT)) {
            throw HttpError::validation(['percent' => 'Скидка — целое число от 0 до ' . LoyaltyTiers::MAX_PERCENT]);
        }
        if ($note !== null && (!is_string($note) || mb_strlen(trim($note)) > 200)) {
            throw HttpError::validation(['note' => 'Не больше 200 символов']);
        }
        $note = is_string($note) && trim($note) !== '' ? trim($note) : null;
        $this->db->run(
            'UPDATE app_users SET loyalty_override_percent = ?, loyalty_override_note = ? WHERE id = ?',
            [$percent, $percent === null ? null : $note, $userId],
        );
        return $this->summary($userId);
    }

    /** @return array{spent: int, count: int} */
    private function spent(int $userId): array
    {
        $row = $this->db->one(
            'SELECT COALESCE(SUM(total), 0) AS spent, COUNT(*) AS cnt FROM app_orders WHERE user_id = ? AND status = ?',
            [$userId, OrderStatus::Completed->value],
        );
        return ['spent' => (int) ($row['spent'] ?? 0), 'count' => (int) ($row['cnt'] ?? 0)];
    }

    /** @return array{percent: int, note: ?string}|null */
    private function override(int $userId): ?array
    {
        $row = $this->db->one('SELECT loyalty_override_percent, loyalty_override_note FROM app_users WHERE id = ?', [$userId]);
        if ($row === null || $row['loyalty_override_percent'] === null) {
            return null;
        }
        return ['percent' => (int) $row['loyalty_override_percent'], 'note' => $row['loyalty_override_note']];
    }
}
