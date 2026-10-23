<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Http\HttpError;
use App\Orders\Composition\CompositionNormalizer;
use PHPUnit\Framework\TestCase;

final class CompositionNormalizerTest extends TestCase
{
    public function testComputesLineSumsSectionTotalsAndTotal(): void
    {
        $result = (new CompositionNormalizer())->normalize([
            'kpNumber' => 'КП-2026-0417',
            'kpDate' => '2026-10-12',
            'sections' => [
                ['title' => 'Мебель', 'lines' => [
                    ['name' => 'Стол Виктория 180', 'art' => '07138', 'qty' => 10, 'days' => 2, 'price' => 462],
                    ['name' => 'Скатерть', 'qty' => 2.5, 'unit' => 'м', 'price' => 100],
                ]],
                ['title' => 'Персонал', 'lines' => [
                    ['name' => 'Официант', 'qty' => 4, 'unit' => 'чел', 'price' => 4500, 'sum' => 17000, 'note' => 'Скидка на смену'],
                ]],
            ],
            'discounts' => [['kind' => 'loyalty', 'title' => 'Скидка постоянного клиента −5%', 'percent' => 5, 'amount' => 1500]],
            'delivery' => 3500,
            'vatNote' => 'Без НДС (УСН)',
        ]);

        $furniture = $result['sections'][0];
        $this->assertSame(9240, $furniture['lines'][0]['sum'], '462 × 10 шт × 2 дня');
        $this->assertSame(250, $furniture['lines'][1]['sum'], 'дробное количество');
        $this->assertSame('шт', $furniture['lines'][0]['unit'], 'единица по умолчанию');
        $this->assertSame(9490, $furniture['subtotal']);
        $this->assertSame(17000, $result['sections'][1]['lines'][0]['sum'], 'сумма из КП важнее расчётной');
        $this->assertSame(26490, $result['subtotal']);
        $this->assertSame(26490 - 1500 + 3500, $result['total']);
        $this->assertSame(['s1', 's2'], array_column($result['sections'], 'id'));
        $this->assertFalse($result['hasOnRequest']);
    }

    public function testExplicitTotalWins(): void
    {
        $result = (new CompositionNormalizer())->normalize([
            'sections' => [['title' => 'Логистика', 'lines' => [['name' => 'Доставка', 'qty' => 1, 'price' => 3500]]]],
            'total' => 3000,
        ]);
        $this->assertSame(3000, $result['total']);
    }

    public function testValidationErrorsPointToFields(): void
    {
        try {
            (new CompositionNormalizer())->normalize([
                'kpDate' => '12.10.2026',
                'sections' => [['title' => '', 'lines' => [['name' => 'Стол', 'qty' => -1, 'price' => 1.5]]]],
            ]);
            $this->fail('ожидалась ошибка валидации');
        } catch (HttpError $e) {
            $this->assertSame(422, $e->status);
            $this->assertArrayHasKey('kpDate', $e->fields);
            $this->assertArrayHasKey('sections.0.title', $e->fields);
            $this->assertArrayHasKey('sections.0.lines.0.qty', $e->fields);
            $this->assertArrayHasKey('sections.0.lines.0.price', $e->fields);
        }
    }

    public function testRejectsEmptyAndOversizedCompositions(): void
    {
        $normalizer = new CompositionNormalizer();
        foreach ([[], ['sections' => []], ['sections' => array_fill(0, 21, ['title' => 'x', 'lines' => [['name' => 'a', 'qty' => 1, 'price' => 1]]])]] as $input) {
            try {
                $normalizer->normalize($input);
                $this->fail('ожидалась ошибка');
            } catch (HttpError $e) {
                $this->assertArrayHasKey('sections', $e->fields);
            }
        }
    }
}
