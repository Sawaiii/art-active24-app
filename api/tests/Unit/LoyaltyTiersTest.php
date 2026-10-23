<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Loyalty\LoyaltyService;
use App\Loyalty\LoyaltyTiers;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

final class LoyaltyTiersTest extends TestCase
{
    public function testDefaultLadderPicksTierBySpentSum(): void
    {
        $tiers = LoyaltyTiers::default();

        $this->assertSame(0, $tiers->tier($tiers->indexFor(0))['percent']);
        $this->assertSame(0, $tiers->tier($tiers->indexFor(49_999))['percent']);
        $this->assertSame(2, $tiers->tier($tiers->indexFor(50_000))['percent']);
        $this->assertSame(5, $tiers->tier($tiers->indexFor(499_999))['percent']);
        $this->assertSame(['level' => 9, 'threshold' => 10_000_000, 'percent' => 25], $tiers->tier($tiers->indexFor(50_000_000)));
        $this->assertCount(9, $tiers->all());
    }

    public function testTiersFromJsonInBothFormats(): void
    {
        $pairs = LoyaltyTiers::fromJson('[[0,0],[1000,3]]');
        $objects = LoyaltyTiers::fromJson('[{"threshold":0,"percent":0},{"threshold":1000,"percent":3}]');

        $this->assertSame($pairs->all(), $objects->all());
        $this->assertSame(3, $pairs->tier($pairs->indexFor(1000))['percent']);
    }

    /** @return iterable<string, array{string}> */
    public static function invalidConfigs(): iterable
    {
        yield 'не JSON' => ['[[0,0'];
        yield 'не с нуля' => ['[[100,1]]'];
        yield 'пороги не растут' => ['[[0,0],[500,2],[500,3]]'];
        yield 'скидка убывает' => ['[[0,5],[500,2]]'];
        yield 'слишком большая скидка' => ['[[0,0],[500,90]]'];
        yield 'дробный порог' => ['[[0,0],[500.5,2]]'];
        yield 'пусто' => ['[]'];
    }

    #[DataProvider('invalidConfigs')]
    public function testInvalidConfigFailsFast(string $json): void
    {
        $this->expectException(\RuntimeException::class);
        LoyaltyTiers::fromJson($json);
    }

    public function testDiscountAmountRoundsHalfUpToWholeRubles(): void
    {
        $this->assertSame(37, LoyaltyService::amount(1848, 2), '36.96 → 37');
        $this->assertSame(1, LoyaltyService::amount(50, 1), '0.50 → 1 (половина — вверх)');
        $this->assertSame(0, LoyaltyService::amount(49, 1), '0.49 → 0');
        $this->assertSame(0, LoyaltyService::amount(1000, 0));
        $this->assertSame(0, LoyaltyService::amount(0, 5));
        $this->assertSame('Скидка постоянного клиента −5%', LoyaltyService::title(5));
    }
}
