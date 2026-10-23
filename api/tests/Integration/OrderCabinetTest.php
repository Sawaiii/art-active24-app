<?php

declare(strict_types=1);

namespace Tests\Integration;

/**
 * Личный кабинет заказа: скидка постоянного клиента, состав, машина, отзыв, претензии, документы.
 */
final class OrderCabinetTest extends ApiTestCase
{
    private const TABLE_2_DAYS = ['productId' => 7138, 'complectId' => 1724, 'time' => ['unit' => 'days', 'value' => 2], 'qty' => 2];
    private const PLOV = ['productId' => 469, 'complectId' => 1590, 'subId' => '1591', 'qty' => 10, 'extras' => [['id' => 'x-povar']]];

    /** @var array{token: string, refresh: string, user: array<string, mixed>} */
    private array $customer;
    /** @var array{token: string, refresh: string, user: array<string, mixed>} */
    private array $manager;

    protected function setUp(): void
    {
        parent::setUp();
        $this->customer = $this->login();
        $this->manager = $this->login(self::MANAGER_PHONE);
    }

    // MARK: Скидка постоянного клиента

    public function testLoyaltyStartsAtZeroAndGrowsWithCompletedOrders(): void
    {
        $loyalty = $this->call('GET', '/v1/me/loyalty', null, $this->customer['token'])['body']['data'];
        $this->assertSame(0, $loyalty['percent']);
        $this->assertSame(['level' => 1, 'threshold' => 0, 'percent' => 0], $loyalty['tier']);
        $this->assertSame(['level' => 2, 'threshold' => 50000, 'percent' => 2, 'remaining' => 50000], $loyalty['nextTier']);
        $this->assertCount(9, $loyalty['tiers']);
        $this->assertArrayNotHasKey('override', $loyalty);

        $id = $this->checkout('cab-0001')['id'];
        $this->moveTo($id, ['confirmed', 'completed'], total: 60000);

        $after = $this->call('GET', '/v1/me/loyalty', null, $this->customer['token'])['body']['data'];
        $this->assertSame(2, $after['percent']);
        $this->assertSame(60000, $after['spent']);
        $this->assertSame(1, $after['completedOrders']);
        $this->assertSame(90000, $after['nextTier']['remaining']);
        $this->assertSame(401, $this->call('GET', '/v1/me/loyalty')['status']);
    }

    public function testDiscountAppliesToQuoteCartAndCheckoutAfterLineTotals(): void
    {
        $guest = $this->call('POST', '/v1/cart/quote', ['items' => [self::TABLE_2_DAYS]])['body']['data'];
        $this->assertSame(1848, $guest['total']);
        $this->assertArrayNotHasKey('discount', $guest, 'без скидки quote прежний');

        $set = $this->call('PUT', "/v1/manager/users/{$this->customer['user']['id']}/loyalty", ['percent' => 5, 'note' => 'Ключевой клиент'], $this->manager['token']);
        $this->assertSame(200, $set['status'], json_encode($set['body'], JSON_UNESCAPED_UNICODE));
        $this->assertSame(['percent' => 5, 'note' => 'Ключевой клиент'], $set['body']['data']['override']);
        $this->assertSame('override', $set['body']['data']['source']);

        $quote = $this->call('POST', '/v1/cart/quote', ['items' => [self::TABLE_2_DAYS]], $this->customer['token'])['body']['data'];
        $this->assertSame(1848, $quote['lines'][0]['total'], 'цены строк не меняются');
        $this->assertSame(1848, $quote['subtotal']);
        $this->assertSame(['kind' => 'loyalty', 'title' => 'Скидка постоянного клиента −5%', 'percent' => 5, 'amount' => 92], $quote['discount']);
        $this->assertSame(1756, $quote['total']);
        $this->assertSame(1756, $this->call('PUT', '/v1/cart', ['items' => [self::TABLE_2_DAYS]], $this->customer['token'])['body']['data']['total']);

        $stale = $this->call('POST', '/v1/cart/quote', ['items' => [self::TABLE_2_DAYS]], 'expired-token');
        $this->assertSame(200, $stale['status'], 'чужой/старый токен — гостевой расчёт, не 401');
        $this->assertSame(1848, $stale['body']['data']['total']);

        $order = $this->checkout('cab-0002');
        $this->assertSame(1756, $order['total']);
        $this->assertSame(1848, $order['subtotal']);
        $this->assertSame(92, $order['discount']['amount']);
        $this->assertStringContainsString('Скидка постоянного клиента −5%: −92 ₽', \App\Orders\OrderText::summary($order));

        $removed = $this->call('PUT', "/v1/manager/users/{$this->customer['user']['id']}/loyalty", ['percent' => null], $this->manager['token']);
        $this->assertSame(0, $removed['body']['data']['percent']);
        $this->assertSame(422, $this->call('PUT', "/v1/manager/users/{$this->customer['user']['id']}/loyalty", ['percent' => 80], $this->manager['token'])['status']);
        $this->assertSame(404, $this->call('GET', '/v1/manager/users/999999/loyalty', null, $this->manager['token'])['status']);
        $this->assertSame(403, $this->call('PUT', "/v1/manager/users/{$this->customer['user']['id']}/loyalty", ['percent' => 5], $this->customer['token'])['status']);
    }

    // MARK: Состав

    public function testCompositionFallsBackToCartLinesGroupedByCategory(): void
    {
        $id = $this->checkout('cab-0003', ['items' => [self::TABLE_2_DAYS, self::PLOV]])['id'];

        $composition = $this->call('GET', "/v1/orders/{$id}/composition", null, $this->customer['token'])['body']['data'];
        $this->assertSame('cart', $composition['source']);
        $this->assertSame(1, $composition['version']);
        $this->assertSame('Мебель', $composition['sections'][0]['title']);
        $table = $composition['sections'][0]['lines'][0];
        $this->assertSame(['name' => 'Стол складной Виктория 180 см — «Технический»', 'days' => 2, 'price' => 924, 'sum' => 1848], [
            'name' => $table['name'], 'days' => $table['days'], 'price' => $table['price'], 'sum' => $table['sum'],
        ]);
        $this->assertSame(13748, $composition['subtotal']);
        $this->assertSame(13748, $composition['total']);
        $this->assertSame('Стоимость доставки рассчитает менеджер', $composition['deliveryNote']);

        $request = $this->call('POST', '/v1/requests', ['kind' => 'callback'], $this->customer['token'], ['Idempotency-Key' => 'cab-req-01'])['body']['data'];
        $empty = $this->call('GET', "/v1/orders/{$request['id']}/composition", null, $this->customer['token'])['body']['data'];
        $this->assertSame(['source' => 'none', 'version' => 1, 'sections' => [], 'subtotal' => 0, 'total' => 0], $empty);
    }

    public function testManagerAttachesKpCompositionAndVersionGrows(): void
    {
        $id = $this->checkout('cab-0004')['id'];
        $kp = [
            'kpNumber' => 'КП-2026-0417',
            'kpDate' => '2026-10-15',
            'sections' => [
                ['title' => 'Мебель', 'lines' => [['name' => 'Стол Виктория 180', 'art' => '07138', 'qty' => 10, 'days' => 2, 'price' => 924]]],
                ['title' => 'Логистика', 'lines' => [['name' => 'Доставка Газель 15 м²', 'qty' => 1, 'price' => 3500]]],
            ],
            'vatNote' => 'Без НДС (УСН)',
        ];
        $put = $this->call('PUT', "/v1/manager/orders/{$id}/composition", $kp, $this->manager['token']);
        $this->assertSame(200, $put['status'], json_encode($put['body'], JSON_UNESCAPED_UNICODE));
        $this->assertSame('manager', $put['body']['data']['source']);
        $this->assertSame(1, $put['body']['data']['version']);
        $this->assertSame(18480 + 3500, $put['body']['data']['total']);

        $this->call('PUT', "/v1/manager/orders/{$id}/composition", $kp, $this->manager['token']);
        $seen = $this->call('GET', "/v1/orders/{$id}/composition", null, $this->customer['token'])['body']['data'];
        $this->assertSame(2, $seen['version']);
        $this->assertSame('КП-2026-0417', $seen['kpNumber']);
        $this->assertSame(['Мебель', 'Логистика'], array_column($seen['sections'], 'title'));

        $bad = $this->call('PUT', "/v1/manager/orders/{$id}/composition", ['sections' => [['title' => 'X', 'lines' => [['name' => 'a', 'qty' => 1]]]]], $this->manager['token']);
        $this->assertSame(422, $bad['status']);
        $this->assertArrayHasKey('sections.0.lines.0.price', $bad['body']['error']['fields']);
        $this->assertSame(403, $this->call('PUT', "/v1/manager/orders/{$id}/composition", $kp, $this->customer['token'])['status']);

        $this->assertSame(204, $this->call('DELETE', "/v1/manager/orders/{$id}/composition", null, $this->manager['token'])['status']);
        $this->assertSame('cart', $this->call('GET', "/v1/orders/{$id}/composition", null, $this->customer['token'])['body']['data']['source']);
    }

    public function testEnabledButUnfinishedKpAdapterFallsBackQuietly(): void
    {
        $this->kernel = $this->buildKernel(['KP_SOURCE_ENABLED' => 'true', 'KP_API_URL' => 'https://kp.example', 'KP_API_TOKEN' => 'secret']);
        $id = $this->checkout('cab-0005')['id'];
        $links = $this->call('PUT', "/v1/manager/orders/{$id}/links", ['crmDealId' => '168093', 'vyzovchatEventId' => 42], $this->manager['token']);
        $this->assertSame(['crmDealId' => '168093', 'vyzovchatEventId' => 42], $links['body']['data']);

        $composition = $this->call('GET', "/v1/orders/{$id}/composition", null, $this->customer['token']);
        $this->assertSame(200, $composition['status']);
        $this->assertSame('cart', $composition['body']['data']['source'], 'сбой «Программы КП» — запасной источник');
        $this->assertSame(422, $this->call('PUT', "/v1/manager/orders/{$id}/links", ['crmDealId' => 'drop table;'], $this->manager['token'])['status']);
    }

    // MARK: Машина на карте

    public function testVehicleTrackingWithDriverTokenAndAntiSpoofing(): void
    {
        $id = $this->checkout('cab-0006')['id'];
        $this->assertSame(409, $this->call('GET', "/v1/orders/{$id}/vehicle", null, $this->customer['token'])['status'], 'пока не в пути');

        $assigned = $this->call('POST', "/v1/manager/orders/{$id}/driver", ['driverName' => 'Сергей', 'vehicle' => 'Газель · А123ВС 777'], $this->manager['token']);
        $this->assertSame(201, $assigned['status']);
        $token = $assigned['body']['data']['token'];
        $this->assertSame("/v1/driver/orders/{$id}/location", $assigned['body']['data']['locationPath']);

        $this->assertSame(401, $this->driver($id, 'f' . str_repeat('0', 47), ['lat' => 55.75, 'lng' => 37.61, 'accuracy' => 10])['status']);
        $this->assertSame(409, $this->driver($id, $token, ['lat' => 55.75, 'lng' => 37.61, 'accuracy' => 10])['status'], 'заказ ещё в обработке');
        $this->moveTo($id, ['confirmed', 'delivering']);

        $first = $this->driver($id, $token, ['lat' => 55.7558, 'lng' => 37.6173, 'accuracy' => 25, 'heading' => 90, 'etaMinutes' => 20]);
        $this->assertSame(['accepted' => true], $first['body']['data']);
        $this->assertSame(['accepted' => false, 'reason' => 'low_accuracy'], $this->driver($id, $token, ['lat' => 55.7558, 'lng' => 37.6173, 'accuracy' => 900])['body']['data']);
        $this->clock->advance(30);
        $this->assertSame('implausible_speed', $this->driver($id, $token, ['lat' => 55.8558, 'lng' => 37.6173, 'accuracy' => 20])['body']['data']['reason'], '11 км за 30 с');
        $this->assertSame('spoof_point', $this->driver($id, $token, ['lat' => 55.5915, 'lng' => 37.2615, 'accuracy' => 15])['body']['data']['reason']);
        $this->assertSame('out_of_region', $this->driver($id, $token, ['lat' => 59.93, 'lng' => 30.31, 'accuracy' => 15])['body']['data']['reason']);
        $this->assertSame(422, $this->driver($id, $token, ['lat' => 'x', 'lng' => 37.6, 'accuracy' => 15])['status']);

        $vehicle = $this->call('GET', "/v1/orders/{$id}/vehicle", null, $this->customer['token'])['body']['data'];
        $this->assertSame('enRoute', $vehicle['status']);
        $this->assertEqualsWithDelta(55.7558, $vehicle['lat'], 1e-6, 'последняя достоверная точка');
        $this->assertSame(25, (int) $vehicle['accuracy']);
        $this->assertSame('2026-10-16T09:22:02Z', $vehicle['eta'], 'время точки (09:02:02 — после двух входов) + 20 мин');
        $this->assertSame('driver', $vehicle['source']);
        $this->assertSame('Газель · А123ВС 777', $vehicle['vehicle']);
        $this->assertTrue($this->order($id)['tracking']);

        $this->clock->advance(660);
        $this->assertSame('unknown', $this->call('GET', "/v1/orders/{$id}/vehicle", null, $this->customer['token'])['body']['data']['status'], 'точка старше 10 минут');
        $this->driver($id, $token, ['lat' => 55.7600, 'lng' => 37.6200, 'accuracy' => 15, 'arrived' => true]);
        $this->assertSame('arrived', $this->call('GET', "/v1/orders/{$id}/vehicle", null, $this->customer['token'])['body']['data']['status']);

        $other = $this->login('+79165550000');
        $this->assertSame(404, $this->call('GET', "/v1/orders/{$id}/vehicle", null, $other['token'])['status']);

        $this->moveTo($id, ['in_progress']);
        $this->assertSame(409, $this->call('GET', "/v1/orders/{$id}/vehicle", null, $this->customer['token'])['status']);
        $this->assertSame(409, $this->driver($id, $token, ['lat' => 55.76, 'lng' => 37.62, 'accuracy' => 15])['status'], 'tracking_closed');
    }

    public function testVehicleWithoutFixAnswersUnknown(): void
    {
        $id = $this->checkout('cab-0007')['id'];
        $this->moveTo($id, ['confirmed', 'delivering']);
        $this->assertSame(['status' => 'unknown'], $this->call('GET', "/v1/orders/{$id}/vehicle", null, $this->customer['token'])['body']['data']);
    }

    // MARK: Отзыв

    public function testReviewAfterCompletionEditableForSevenDays(): void
    {
        $id = $this->checkout('cab-0008')['id'];
        $this->assertSame(409, $this->review($id, ['rating' => 5])['status'], 'до завершения');
        $this->assertFalse($this->order($id)['canReview']);
        $this->moveTo($id, ['confirmed', 'completed']);
        $this->assertTrue($this->order($id)['canReview']);

        $this->assertSame(422, $this->review($id, ['rating' => 6])['status']);
        $created = $this->review($id, ['rating' => 4, 'text' => '  Всё привезли вовремя  ']);
        $this->assertSame(201, $created['status']);
        $this->assertSame(['rating' => 4, 'text' => 'Всё привезли вовремя'], ['rating' => $created['body']['data']['rating'], 'text' => $created['body']['data']['text']]);
        $this->assertTrue($created['body']['data']['canEdit']);

        $this->advanceDays(3);
        $edited = $this->review($id, ['rating' => 5]);
        $this->assertSame(200, $edited['status']);
        $this->assertSame(5, $this->order($id)['review']['rating']);
        $this->assertArrayNotHasKey('text', $edited['body']['data'], 'текст можно убрать');

        $this->advanceDays(5);
        $this->assertSame('review_locked', $this->review($id, ['rating' => 1])['body']['error']['code']);
        $this->assertFalse($this->order($id)['canReview']);
        $this->assertFalse($this->order($id)['review']['canEdit']);
    }

    // MARK: Претензия

    public function testClaimWindowManagerAcceptsAndChatLinkAppears(): void
    {
        $id = $this->checkout('cab-0009')['id'];
        $body = ['category' => 'late', 'description' => 'Машина приехала на два часа позже', 'contactPreference' => 'messenger'];
        $this->assertSame('claim_unavailable', $this->claim($id, $body)['body']['error']['code']);
        $this->assertFalse($this->order($id)['canClaim']);

        $this->moveTo($id, ['confirmed', 'in_progress']);
        $this->assertTrue($this->order($id)['canClaim']);
        $invalid = $this->claim($id, ['category' => 'weather', 'description' => 'коротко', 'photos' => [['url' => 'http://x.ru/a.jpg']]]);
        $this->assertSame(422, $invalid['status']);
        $this->assertSame(['category', 'description', 'photos.0.url'], array_keys($invalid['body']['error']['fields']));

        $created = $this->claim($id, $body + ['photos' => [['url' => 'https://cdn.example/p1.jpg']]]);
        $this->assertSame(201, $created['status'], json_encode($created['body'], JSON_UNESCAPED_UNICODE));
        $claim = $created['body']['data'];
        $this->assertSame(['submitted', 'Отправлена', 'Опоздание'], [$claim['status'], $claim['statusLabel'], $claim['categoryLabel']]);
        $this->assertArrayNotHasKey('chatUrl', $claim);
        $this->assertSame([['url' => 'https://cdn.example/p1.jpg']], $claim['photos']);

        $managerList = $this->call('GET', '/v1/manager/claims?status=submitted', null, $this->manager['token']);
        $this->assertSame([$claim['id']], array_column($managerList['body']['data'], 'id'));
        $this->assertSame(403, $this->call('GET', '/v1/manager/claims', null, $this->customer['token'])['status']);

        $accepted = $this->call('PATCH', "/v1/manager/claims/{$claim['id']}", ['status' => 'accepted', 'comment' => 'Разберёмся в чате'], $this->manager['token']);
        $this->assertSame(200, $accepted['status']);
        $this->assertSame('https://vyzovchat.ru/', $accepted['body']['data']['chatUrl'], 'интеграция выключена — общий адрес');
        $this->assertSame('Разберёмся в чате', $this->push->sent[array_key_last($this->push->sent)]['body']);
        $this->assertSame('accepted', $this->order($id)['claims'][0]['status']);

        $this->assertSame(409, $this->call('PATCH', "/v1/manager/claims/{$claim['id']}", ['status' => 'rejected'], $this->manager['token'])['status']);
        $this->assertSame('resolved', $this->call('PATCH', "/v1/manager/claims/{$claim['id']}", ['status' => 'resolved'], $this->manager['token'])['body']['data']['status']);
    }

    public function testManagerChatLinkGetsAppSchemeAndOpenClaimsAreLimited(): void
    {
        $id = $this->checkout('cab-0010')['id'];
        $this->moveTo($id, ['confirmed', 'completed']);
        $body = ['category' => 'quality', 'description' => 'Скатерти были в пятнах, пришлось менять'];
        $ids = [];
        for ($i = 0; $i < 3; $i++) {
            $ids[] = $this->claim($id, $body)['body']['data']['id'];
        }
        $this->assertSame('claim_limit', $this->claim($id, $body)['body']['error']['code']);

        $accepted = $this->call('PATCH', "/v1/manager/claims/{$ids[0]}", [
            'status' => 'accepted', 'chatUrl' => 'https://vyzovchat.ru/join/AbCdEf123456',
        ], $this->manager['token'])['body']['data'];
        $this->assertSame('vyzovchat://join/AbCdEf123456', $accepted['chatAppUrl']);
        $this->assertSame(422, $this->call('PATCH', "/v1/manager/claims/{$ids[1]}", ['status' => 'accepted', 'chatUrl' => 'javascript:alert(1)'], $this->manager['token'])['status']);
        $this->assertSame('rejected', $this->call('PATCH', "/v1/manager/claims/{$ids[2]}", ['status' => 'rejected'], $this->manager['token'])['body']['data']['status']);

        $this->advanceDays(15);
        $this->assertFalse($this->order($id)['canClaim'], '14 дней после завершения прошли');
        $this->assertSame('claim_unavailable', $this->claim($id, $body)['body']['error']['code']);
    }

    // MARK: Документы

    public function testDocumentsFromManagerAndCrm(): void
    {
        $this->kernel = $this->buildKernel(['CRM_DOCUMENTS_ENABLED' => 'true', 'CRM_ACT_URL_TEMPLATE' => 'https://crm.example/act/?id=<ORDERID>']);
        $id = $this->checkout('cab-0011')['id'];
        $this->assertSame([], $this->call('GET', "/v1/orders/{$id}/documents", null, $this->customer['token'])['body']['data']);

        $added = $this->call('POST', "/v1/manager/orders/{$id}/documents", [
            'title' => 'Договор аренды № 417', 'kind' => 'contract', 'url' => 'https://disk.example/d/417.pdf',
            'date' => '2026-10-15', 'size' => 184320, 'mime' => 'application/pdf',
        ], $this->manager['token']);
        $this->assertSame(201, $added['status'], json_encode($added['body'], JSON_UNESCAPED_UNICODE));
        $this->assertSame('m-1', $added['body']['data']['id']);
        $this->assertSame(422, $this->call('POST', "/v1/manager/orders/{$id}/documents", [
            'title' => 'Счёт', 'kind' => 'bill', 'url' => 'http://disk.example/a.pdf',
        ], $this->manager['token'])['status']);

        $this->call('PUT', "/v1/manager/orders/{$id}/links", ['crmDealId' => '168093'], $this->manager['token']);
        $docs = $this->call('GET', "/v1/orders/{$id}/documents", null, $this->customer['token'])['body']['data'];
        $this->assertSame(['m-1', 'crm-act'], array_column($docs, 'id'));
        $this->assertSame('https://crm.example/act/?id=168093', $docs[1]['url']);
        $this->assertSame(['manager', 'crm'], array_column($docs, 'source'));

        $this->assertSame(204, $this->call('DELETE', "/v1/manager/orders/{$id}/documents/m-1", null, $this->manager['token'])['status']);
        $this->assertSame(404, $this->call('DELETE', "/v1/manager/orders/{$id}/documents/m-1", null, $this->manager['token'])['status']);
        $other = $this->login('+79165550001');
        $this->assertSame(404, $this->call('GET', "/v1/orders/{$id}/documents", null, $other['token'])['status']);
    }

    // MARK: Помощники

    /** Сдвиг часов на дни: access-токены (30 мин) истекают — входим заново. */
    private function advanceDays(int $days): void
    {
        $this->clock->advance($days * 86400);
        $this->customer = $this->login();
        $this->manager = $this->login(self::MANAGER_PHONE);
    }

    /**
     * @param array<string, mixed> $override
     * @return array<string, mixed> Order
     */
    private function checkout(string $key, array $override = []): array
    {
        $res = $this->call('POST', '/v1/orders', $override + [
            'items' => [self::TABLE_2_DAYS],
            'eventDate' => '2026-11-01',
            'delivery' => ['method' => 'delivery', 'address' => 'Москва, Тверская 1'],
        ], $this->customer['token'], ['Idempotency-Key' => $key]);
        $this->assertSame(201, $res['status'], json_encode($res['body'], JSON_UNESCAPED_UNICODE));
        return $res['body']['data'];
    }

    /** @param list<string> $statuses */
    private function moveTo(int $id, array $statuses, ?int $total = null): void
    {
        foreach ($statuses as $status) {
            $body = ['status' => $status] + ($total === null ? [] : ['total' => $total]);
            $res = $this->call('PATCH', "/v1/manager/orders/{$id}", $body, $this->manager['token']);
            $this->assertSame(200, $res['status'], json_encode($res['body'], JSON_UNESCAPED_UNICODE));
        }
    }

    /** @return array<string, mixed> */
    private function order(int $id): array
    {
        return $this->call('GET', "/v1/orders/{$id}", null, $this->customer['token'])['body']['data'];
    }

    /**
     * @param array<string, mixed> $body
     * @return array{status: int, body: array<string, mixed>}
     */
    private function driver(int $id, string $token, array $body): array
    {
        return $this->call('POST', "/v1/driver/orders/{$id}/location", $body, $token);
    }

    /**
     * @param array<string, mixed> $body
     * @return array{status: int, body: array<string, mixed>}
     */
    private function review(int $id, array $body): array
    {
        return $this->call('POST', "/v1/orders/{$id}/review", $body, $this->customer['token']);
    }

    /**
     * @param array<string, mixed> $body
     * @return array{status: int, body: array<string, mixed>}
     */
    private function claim(int $id, array $body): array
    {
        return $this->call('POST', "/v1/orders/{$id}/claims", $body, $this->customer['token']);
    }
}
