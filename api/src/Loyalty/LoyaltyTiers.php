<?php

declare(strict_types=1);

namespace App\Loyalty;

/**
 * Лестница скидок постоянного клиента: порог суммы завершённых заказов (₽) → скидка (%).
 * Настраивается LOYALTY_TIERS (JSON) или LOYALTY_TIERS_FILE (путь к JSON); формат —
 * [[0,0],[50000,2],…] или [{"threshold":0,"percent":0},…]. Ошибка формата — отказ старта.
 */
final class LoyaltyTiers
{
    public const MAX_PERCENT = 50;

    /** Порог → процент по умолчанию. */
    public const DEFAULT = [
        [0, 0], [50_000, 2], [150_000, 3], [300_000, 5], [500_000, 7],
        [1_000_000, 10], [2_000_000, 15], [5_000_000, 20], [10_000_000, 25],
    ];

    /** @param list<array{threshold: int, percent: int}> $tiers */
    private function __construct(private readonly array $tiers)
    {
    }

    public static function default(): self
    {
        return self::fromList(self::DEFAULT);
    }

    public static function fromJson(string $json): self
    {
        try {
            $data = json_decode($json, true, 8, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            throw new \RuntimeException('LOYALTY_TIERS: некорректный JSON');
        }
        if (!is_array($data) || !array_is_list($data)) {
            throw new \RuntimeException('LOYALTY_TIERS: ожидается список уровней');
        }
        return self::fromList($data);
    }

    /** @param list<mixed> $raw */
    public static function fromList(array $raw): self
    {
        $tiers = [];
        foreach ($raw as $i => $tier) {
            $threshold = is_array($tier) ? ($tier['threshold'] ?? $tier[0] ?? null) : null;
            $percent = is_array($tier) ? ($tier['percent'] ?? $tier[1] ?? null) : null;
            if (!is_int($threshold) || !is_int($percent) || $threshold < 0 || $percent < 0 || $percent > self::MAX_PERCENT) {
                throw new \RuntimeException("LOYALTY_TIERS: уровень {$i} — нужны целые threshold ≥ 0 и percent 0…" . self::MAX_PERCENT);
            }
            $previous = $tiers === [] ? null : $tiers[count($tiers) - 1];
            if ($previous !== null && ($threshold <= $previous['threshold'] || $percent < $previous['percent'])) {
                throw new \RuntimeException('LOYALTY_TIERS: пороги строго растут, скидка не убывает');
            }
            $tiers[] = ['threshold' => $threshold, 'percent' => $percent];
        }
        if ($tiers === [] || $tiers[0]['threshold'] !== 0) {
            throw new \RuntimeException('LOYALTY_TIERS: первый уровень — с порога 0');
        }
        return new self($tiers);
    }

    /** Индекс уровня для суммы. */
    public function indexFor(int $spent): int
    {
        $index = 0;
        foreach ($this->tiers as $i => $tier) {
            if ($spent >= $tier['threshold']) {
                $index = $i;
            }
        }
        return $index;
    }

    /** @return array{level: int, threshold: int, percent: int} */
    public function tier(int $index): array
    {
        return ['level' => $index + 1] + $this->tiers[$index];
    }

    public function count(): int
    {
        return count($this->tiers);
    }

    /** @return list<array{level: int, threshold: int, percent: int}> */
    public function all(): array
    {
        return array_map(fn (int $i) => $this->tier($i), array_keys($this->tiers));
    }
}
