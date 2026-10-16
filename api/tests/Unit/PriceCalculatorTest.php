<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Http\HttpError;
use App\Pricing\CartItem;
use App\Pricing\PriceCalculator;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

final class PriceCalculatorTest extends TestCase
{
    /** @return iterable<string, array{array<string, mixed>}> */
    public static function vectors(): iterable
    {
        $file = dirname(__DIR__, 3) . '/contract/pricing-vectors.json';
        $data = json_decode((string) file_get_contents($file), true, 64, JSON_THROW_ON_ERROR);
        foreach ($data['vectors'] as $vector) {
            yield $vector['name'] => [$vector];
        }
    }

    /** @param array<string, mixed> $vector */
    #[DataProvider('vectors')]
    public function testMatchesSharedVector(array $vector): void
    {
        $complect = ['id' => 1, 'title' => 'Комплект'] + $vector['complect'];
        $item = CartItem::fromArray(['productId' => 1, 'complectId' => 1] + $vector['input']);

        if (isset($vector['expect']['error'])) {
            try {
                (new PriceCalculator())->price($complect, $vector['extras'] ?? [], $item);
                $this->fail('Ожидалась ошибка валидации');
            } catch (HttpError $e) {
                $this->assertArrayHasKey($vector['expect']['error'], $e->fields);
            }
            return;
        }

        $result = (new PriceCalculator())->price($complect, $vector['extras'] ?? [], $item);

        $this->assertSame($vector['expect']['unitPrice'], $result->unitPrice, 'unitPrice');
        $this->assertSame($vector['expect']['total'], $result->total, 'total');
        $this->assertSame($vector['expect']['timeLabel'], $result->timeLabel, 'timeLabel');
        $this->assertSame($vector['expect']['onRequest'], $result->onRequest, 'onRequest');
    }

    public function testRejectsHoursAboveEightForHourlyRule(): void
    {
        $complect = ['id' => 1, 'title' => 'К', 'rent' => ['amount' => 1000, 'label' => 'Аренда'],
            'time' => ['unit' => 'hours', 'default' => 6, 'percent' => 10]];
        $item = CartItem::fromArray(['productId' => 1, 'complectId' => 1, 'qty' => 1,
            'time' => ['unit' => 'hours', 'value' => 9]]);

        $this->expectException(HttpError::class);
        (new PriceCalculator())->price($complect, [], $item);
    }

    public function testRejectsDaysBelowDefault(): void
    {
        $complect = ['id' => 1, 'title' => 'К', 'rent' => ['amount' => 1000, 'label' => 'Аренда'],
            'time' => ['unit' => 'days', 'default' => 2, 'percent' => 10]];
        $item = CartItem::fromArray(['productId' => 1, 'complectId' => 1, 'qty' => 1,
            'time' => ['unit' => 'days', 'value' => 1]]);

        $this->expectException(HttpError::class);
        (new PriceCalculator())->price($complect, [], $item);
    }

    public function testRejectsUnknownExtra(): void
    {
        $complect = ['id' => 1, 'title' => 'К', 'rent' => ['amount' => 1000, 'label' => 'Аренда']];
        $item = CartItem::fromArray(['productId' => 1, 'complectId' => 1, 'qty' => 1, 'extras' => [['id' => 'nope']]]);

        $this->expectException(HttpError::class);
        (new PriceCalculator())->price($complect, [], $item);
    }

    public function testRequiresVariantWhenComplectHasVariants(): void
    {
        $complect = ['id' => 1, 'title' => 'К', 'rent' => ['amount' => 0, 'label' => 'Аренда'],
            'subs' => [['id' => 's1', 'name' => 'A', 'rent' => ['amount' => 100, 'label' => 'Аренда']]]];
        $item = CartItem::fromArray(['productId' => 1, 'complectId' => 1, 'qty' => 1]);

        $this->expectException(HttpError::class);
        (new PriceCalculator())->price($complect, [], $item);
    }

    public function testRejectsBuyWhenComplectHasNoBuyPrice(): void
    {
        $complect = ['id' => 1, 'title' => 'К', 'rent' => ['amount' => 1000, 'label' => 'Аренда']];
        $item = CartItem::fromArray(['productId' => 1, 'complectId' => 1, 'qty' => 1, 'priceType' => 'buy']);

        $this->expectException(HttpError::class);
        (new PriceCalculator())->price($complect, [], $item);
    }

    public function testCapacityPostfixGivesPieces(): void
    {
        $complect = ['id' => 1, 'title' => 'К', 'rent' => ['amount' => 11000, 'label' => 'Аренда', 'postfix' => '/ до 40 чел']];
        $item = CartItem::fromArray(['productId' => 1, 'complectId' => 1, 'qty' => 1]);

        $this->assertSame('шт', (new PriceCalculator())->price($complect, [], $item)->qtyUnit);
    }

    public function testQtyUnitComesFromPostfix(): void
    {
        $complect = ['id' => 1, 'title' => 'К', 'rent' => ['amount' => 340, 'label' => 'Аренда', 'postfix' => '/ порц.']];
        $item = CartItem::fromArray(['productId' => 1, 'complectId' => 1, 'qty' => 2]);

        $result = (new PriceCalculator())->price($complect, [], $item);

        $this->assertSame('порц.', $result->qtyUnit);
    }
}
