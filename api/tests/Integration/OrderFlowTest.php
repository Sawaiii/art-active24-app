<?php

declare(strict_types=1);

namespace Tests\Integration;

final class OrderFlowTest extends ApiTestCase
{
    private const TABLE_2_DAYS = ['productId' => 7138, 'complectId' => 1724, 'time' => ['unit' => 'days', 'value' => 2], 'qty' => 2];
    private const PLOV = ['productId' => 469, 'complectId' => 1590, 'subId' => '1591', 'qty' => 10, 'extras' => [['id' => 'x-povar']]];

    public function testQuoteRepricesOnServerAndFlagsUnavailable(): void
    {
        $res = $this->call('POST', '/v1/cart/quote', ['items' => [
            self::TABLE_2_DAYS,
            self::PLOV,
            ['productId' => 3344, 'complectId' => 1, 'qty' => 1],
            ['productId' => 999999, 'complectId' => 1, 'qty' => 1],
        ]]);

        $lines = $res['body']['data']['lines'];
        $this->assertSame([1848, 11900], [$lines[0]['total'], $lines[1]['total']]);
        $this->assertSame('2 д', $lines[0]['timeLabel']);
        $this->assertSame([true, true, false, false], array_column($lines, 'available'));
        $this->assertSame(13748, $res['body']['data']['total'], 'недоступные позиции в итог не входят');
    }

    public function testCheckoutCreatesProcessingOrderVisibleInProfile(): void
    {
        $s = $this->login();
        $this->call('PUT', '/v1/cart', ['items' => [self::TABLE_2_DAYS]], $s['token']);

        $res = $this->checkout($s['token'], 'key-00000001');

        $this->assertSame(201, $res['status'], json_encode($res['body'], JSON_UNESCAPED_UNICODE));
        $order = $res['body']['data'];
        $this->assertSame('processing', $order['status']);
        $this->assertSame('В обработке', $order['statusLabel']);
        $this->assertSame('AA-000001', $order['number']);
        $this->assertSame(1848, $order['total']);
        $this->assertTrue($order['canCancel']);
        $this->assertCount(1, $order['history']);
        $this->assertCount(1, $this->notifier->created, 'менеджеры уведомлены');
        $this->assertStringContainsString('арт.: 07138', \App\Orders\OrderText::summary($order));

        $this->assertSame([], $this->call('GET', '/v1/cart', null, $s['token'])['body']['data']['lines'], 'корзина очищена');
        $list = $this->call('GET', '/v1/orders', null, $s['token']);
        $this->assertSame([$order['id']], array_column($list['body']['data'], 'id'));
    }

    public function testCheckoutIsIdempotent(): void
    {
        $s = $this->login();
        $first = $this->checkout($s['token'], 'key-00000002');
        $second = $this->checkout($s['token'], 'key-00000002');

        $this->assertSame($first['body']['data']['id'], $second['body']['data']['id']);
        $this->assertCount(1, $this->notifier->created);
    }

    public function testCheckoutValidation(): void
    {
        $s = $this->login();

        $past = $this->checkout($s['token'], 'key-00000003', ['eventDate' => '2026-10-15']);
        $this->assertSame(422, $past['status']);
        $this->assertArrayHasKey('eventDate', $past['body']['error']['fields']);

        $noAddress = $this->checkout($s['token'], 'key-00000004', ['delivery' => ['method' => 'delivery']]);
        $this->assertArrayHasKey('delivery.address', $noAddress['body']['error']['fields']);

        $requestOnly = $this->checkout($s['token'], 'key-00000005', ['items' => [['productId' => 3344, 'complectId' => 1, 'qty' => 1]]]);
        $this->assertSame(409, $requestOnly['status']);

        $noKey = $this->call('POST', '/v1/orders', $this->checkoutBody([]), $s['token']);
        $this->assertSame(400, $noKey['status']);

        $this->assertSame(401, $this->call('POST', '/v1/orders', $this->checkoutBody([]))['status']);
    }

    public function testRequestWithoutCartGoesToOrders(): void
    {
        $s = $this->login();
        $res = $this->call('POST', '/v1/requests', ['kind' => 'product', 'productId' => 3344, 'comment' => 'Нужно 3 хостес'], $s['token'], ['Idempotency-Key' => 'req-00000001']);

        $this->assertSame(201, $res['status']);
        $this->assertSame('Хостес', $res['body']['data']['subject']);
        $this->assertSame('product', $res['body']['data']['kind']);

        $venue = $this->call('POST', '/v1/requests', ['kind' => 'venue', 'venueId' => 1, 'eventDate' => '2026-11-01', 'guests' => 50], $s['token'], ['Idempotency-Key' => 'req-00000002']);
        $this->assertSame('Площадка: Loft Idealista', $venue['body']['data']['subject']);
    }

    public function testCustomerCancelsOnlyWhileProcessing(): void
    {
        $s = $this->login();
        $manager = $this->login(self::MANAGER_PHONE);
        $id = $this->checkout($s['token'], 'key-00000006')['body']['data']['id'];
        $id2 = $this->checkout($s['token'], 'key-00000007')['body']['data']['id'];

        $cancelled = $this->call('POST', "/v1/orders/{$id}/cancel", null, $s['token']);
        $this->assertSame('cancelled', $cancelled['body']['data']['status']);

        $this->call('PATCH', "/v1/manager/orders/{$id2}", ['status' => 'confirmed'], $manager['token']);
        $this->assertSame(409, $this->call('POST', "/v1/orders/{$id2}/cancel", null, $s['token'])['status']);
    }

    public function testManagerMovesStatusAndCustomerGetsPush(): void
    {
        $s = $this->login();
        $manager = $this->login(self::MANAGER_PHONE);
        $id = $this->checkout($s['token'], 'key-00000008')['body']['data']['id'];

        $this->assertSame(403, $this->call('GET', '/v1/manager/orders', null, $s['token'])['status']);
        $this->assertSame([$id], array_column($this->call('GET', '/v1/manager/orders?status=processing', null, $manager['token'])['body']['data'], 'id'));

        $res = $this->call('PATCH', "/v1/manager/orders/{$id}", ['status' => 'confirmed', 'comment' => 'Ждём вас 1 ноября', 'total' => 2000], $manager['token']);
        $this->assertSame('Подтверждён', $res['body']['data']['statusLabel']);
        $this->assertSame(2000, $res['body']['data']['total']);
        $this->assertSame('Ждём вас 1 ноября', $res['body']['data']['history'][1]['comment']);
        $this->assertSame((int) $s['user']['id'], $this->push->sent[0]['userId']);

        $invalid = $this->call('PATCH', "/v1/manager/orders/{$id}", ['status' => 'processing'], $manager['token']);
        $this->assertSame(409, $invalid['status']);
    }

    public function testManagerOpensSingleOrderSearchesAndSeesRequestDetails(): void
    {
        $s = $this->login('+79163334455');
        $manager = $this->login(self::MANAGER_PHONE);
        $venue = $this->call('POST', '/v1/requests', ['kind' => 'venue', 'venueId' => 1, 'eventDate' => '2026-11-01',
            'guests' => 50, 'eventType' => 'Корпоратив'], $s['token'], ['Idempotency-Key' => 'req-venue-01'])['body']['data'];
        $this->checkout($s['token'], 'key-search-01');

        $single = $this->call('GET', "/v1/manager/orders/{$venue['id']}", null, $manager['token']);
        $this->assertSame(['venueId' => 1, 'eventType' => 'Корпоратив', 'guests' => 50], $single['body']['data']['details']);
        $this->assertSame(403, $this->call('GET', "/v1/manager/orders/{$venue['id']}", null, $s['token'])['status']);

        $byPhone = $this->call('GET', '/v1/manager/orders?q=' . rawurlencode('8 (916) 333'), null, $manager['token']);
        $this->assertSame(2, $byPhone['body']['meta']['total']);
        $byNumber = $this->call('GET', '/v1/manager/orders?q=' . $venue['number'], null, $manager['token']);
        $this->assertSame([$venue['id']], array_column($byNumber['body']['data'], 'id'));
        $bySubject = $this->call('GET', '/v1/manager/orders?q=Loft', null, $manager['token']);
        $this->assertSame([$venue['id']], array_column($bySubject['body']['data'], 'id'));
        $wildcard = $this->call('GET', '/v1/manager/orders?q=' . rawurlencode('%'), null, $manager['token']);
        $this->assertSame(0, $wildcard['body']['meta']['total'], '«%» ищется буквально');
    }

    public function testCustomerCannotSeeSomeoneElsesOrder(): void
    {
        $owner = $this->login('+79161111111');
        $other = $this->login('+79162222222');
        $id = $this->checkout($owner['token'], 'key-00000009')['body']['data']['id'];

        $this->assertSame(404, $this->call('GET', "/v1/orders/{$id}", null, $other['token'])['status']);
    }

    public function testOptionLineForToggleTemplateIsPricedFromExtras(): void
    {
        $res = $this->call('POST', '/v1/cart/quote', ['items' => [
            ['productId' => 1055, 'qty' => 1, 'extras' => [['id' => 'x-barmen']]],
            ['productId' => 7138, 'qty' => 1, 'extras' => [['id' => 'x-any']]],
        ]]);

        $lines = $res['body']['data']['lines'];
        $this->assertTrue($lines[0]['available']);
        $this->assertSame(8000, $lines[0]['total']);
        $this->assertSame('Бармен', $lines[0]['complectTitle']);
        $this->assertFalse($lines[1]['available'], 'у товара с конфигуратором доп без комплекта не продаётся');

        $bad = $this->call('POST', '/v1/cart/quote', ['items' => [['productId' => 1055, 'qty' => 1]]]);
        $this->assertSame(422, $bad['status'], 'без комплекта нужен хотя бы один доп');
    }

    public function testCartPutMergesSameConfiguration(): void
    {
        $s = $this->login();
        $res = $this->call('PUT', '/v1/cart', ['items' => [self::TABLE_2_DAYS, self::TABLE_2_DAYS]], $s['token']);

        $this->assertCount(1, $res['body']['data']['lines']);
        $this->assertSame(4, $res['body']['data']['lines'][0]['input']['qty']);
    }

    public function testFavoritesRoundTrip(): void
    {
        $s = $this->login();
        $res = $this->call('PUT', '/v1/me/favorites', ['productIds' => [469, 7138, 999999]], $s['token']);

        $this->assertSame([469, 7138], array_column($res['body']['data']['items'], 'id'));
    }

    /**
     * @param array<string, mixed> $override
     * @return array{status: int, body: array<string, mixed>}
     */
    private function checkout(string $token, string $key, array $override = []): array
    {
        return $this->call('POST', '/v1/orders', $this->checkoutBody($override), $token, ['Idempotency-Key' => $key]);
    }

    /**
     * @param array<string, mixed> $override
     * @return array<string, mixed>
     */
    private function checkoutBody(array $override): array
    {
        return $override + [
            'items' => [self::TABLE_2_DAYS],
            'eventDate' => '2026-11-01',
            'delivery' => ['method' => 'delivery', 'address' => 'Москва, Тверская 1'],
            'contactName' => 'Анна',
        ];
    }
}
