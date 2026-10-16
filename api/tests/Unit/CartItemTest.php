<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Http\HttpError;
use App\Pricing\CartItem;
use PHPUnit\Framework\TestCase;

final class CartItemTest extends TestCase
{
    public function testParsesFullInput(): void
    {
        $item = CartItem::fromArray([
            'productId' => 7138, 'complectId' => 1724, 'subId' => 's1', 'priceType' => 'rent',
            'time' => ['unit' => 'days', 'value' => 2], 'qty' => 3,
            'extras' => [['id' => 'x-a'], ['id' => 'x-b', 'qty' => 2]],
            'menu' => [['id' => 'm1', 'qty' => 5]],
        ]);

        $this->assertSame(7138, $item->productId);
        $this->assertSame('days', $item->timeUnit);
        $this->assertSame(2, $item->timeValue);
        $this->assertSame(['x-a' => 1, 'x-b' => 2], $item->extras);
        $this->assertSame(['m1' => 5], $item->menu);
    }

    public function testKeyIsStableForSameConfigurationRegardlessOfExtrasOrder(): void
    {
        $a = CartItem::fromArray(['productId' => 1, 'complectId' => 2, 'qty' => 1, 'extras' => [['id' => 'a'], ['id' => 'b']]]);
        $b = CartItem::fromArray(['productId' => 1, 'complectId' => 2, 'qty' => 5, 'extras' => [['id' => 'b'], ['id' => 'a']]]);

        $this->assertSame($a->key(), $b->key());
    }

    public function testRejectsNonPositiveQty(): void
    {
        try {
            CartItem::fromArray(['productId' => 1, 'complectId' => 2, 'qty' => 0]);
            $this->fail('Ожидалась ошибка валидации');
        } catch (HttpError $e) {
            $this->assertSame(422, $e->status);
            $this->assertArrayHasKey('qty', $e->fields);
        }
    }

    public function testRejectsUnknownPriceType(): void
    {
        $this->expectException(HttpError::class);
        CartItem::fromArray(['productId' => 1, 'complectId' => 2, 'qty' => 1, 'priceType' => 'gift']);
    }

    public function testToArrayRoundTrips(): void
    {
        $input = ['productId' => 1, 'complectId' => 2, 'subId' => 's', 'priceType' => 'buy',
            'time' => ['unit' => 'hours', 'value' => 7], 'qty' => 4,
            'extras' => [['id' => 'e', 'qty' => 1]], 'menu' => [['id' => 'm', 'qty' => 3]]];

        $this->assertSame($input, CartItem::fromArray($input)->toArray());
    }
}
