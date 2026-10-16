<?php

declare(strict_types=1);

namespace Tests\Integration;

use App\Auth\SmsSender;
use App\Auth\PhoneNumber;
use App\Config;
use App\Container;
use App\Kernel;

/**
 * Регрессии по находкам security- и code-ревью.
 */
final class SecurityTest extends ApiTestCase
{
    public function testManagerLosesAccessImmediatelyWhenRemovedFromConfig(): void
    {
        $manager = $this->login(self::MANAGER_PHONE);
        $this->assertSame(200, $this->call('GET', '/v1/manager/orders', null, $manager['token'])['status']);

        $this->kernel = $this->buildKernel(['MANAGER_PHONES' => '']);

        $this->assertSame(403, $this->call('GET', '/v1/manager/orders', null, $manager['token'])['status']);
        $this->assertSame('customer', $this->call('GET', '/v1/me', null, $manager['token'])['body']['data']['role']);
    }

    public function testReviewPhoneCannotBeManager(): void
    {
        $this->expectException(\RuntimeException::class);
        $this->buildKernel(['AUTH_REVIEW_PHONE' => self::MANAGER_PHONE, 'AUTH_REVIEW_CODE' => '123456']);
    }

    public function testWeakPepperIsRejected(): void
    {
        $this->expectException(\RuntimeException::class);
        $this->buildKernel(['AUTH_PEPPER' => 'change-me-to-64-random-chars']);
    }

    public function testProductionRefusesLogSmsAndMissingOrderEmails(): void
    {
        $base = ['APP_ENV' => 'production', 'AUTH_PEPPER' => str_repeat('x', 40), 'LOG_FILE' => 'off',
            'SNAPSHOT_DIR' => dirname(__DIR__) . '/fixtures/snapshot'];
        try {
            new Container(Config::fromArray($base), $this->db, $this->clock);
            $this->fail('production без SMS-провайдера не должен стартовать');
        } catch (\RuntimeException $e) {
            $this->assertStringContainsString('SMS', $e->getMessage());
        }
        $this->expectExceptionMessage('ORDER_NOTIFY_EMAILS');
        new Container(Config::fromArray($base), $this->db, $this->clock, $this->sms);
    }

    public function testReviewLoginWorksWithoutSms(): void
    {
        $this->kernel = $this->buildKernel(['AUTH_REVIEW_PHONE' => '+79005553535', 'AUTH_REVIEW_CODE' => '424242']);
        $this->call('POST', '/v1/auth/code', ['phone' => '+79005553535']);

        $this->assertNull($this->sms->lastTextFor('+79005553535'));
        $res = $this->call('POST', '/v1/auth/verify', ['phone' => '+79005553535', 'code' => '424242']);
        $this->assertSame('customer', $res['body']['data']['user']['role']);
    }

    public function testVerifyIsRateLimitedPerPhone(): void
    {
        for ($i = 0; $i < 10; $i++) {
            $this->call('POST', '/v1/auth/verify', ['phone' => '+79161234567', 'code' => '000000']);
        }
        $this->assertSame(429, $this->call('POST', '/v1/auth/verify', ['phone' => '+79161234567', 'code' => '000000'])['status']);
    }

    public function testCodeCannotBeUsedTwice(): void
    {
        $this->call('POST', '/v1/auth/code', ['phone' => '+79161234567']);
        preg_match('/(\d{6})/', (string) $this->sms->lastTextFor('+79161234567'), $m);

        $this->assertSame(200, $this->call('POST', '/v1/auth/verify', ['phone' => '+79161234567', 'code' => $m[1]])['status']);
        $this->assertSame(422, $this->call('POST', '/v1/auth/verify', ['phone' => '+79161234567', 'code' => $m[1]])['status']);
    }

    public function testSmsProviderFailureIs503(): void
    {
        $failing = new class implements SmsSender {
            public function send(PhoneNumber $phone, string $text): void
            {
                throw new \RuntimeException('provider down');
            }
        };
        $config = Config::fromArray(['APP_ENV' => 'test', 'LOG_FILE' => 'off', 'AUTH_PEPPER' => str_repeat('p', 40),
            'SNAPSHOT_DIR' => dirname(__DIR__) . '/fixtures/snapshot']);
        $this->kernel = new Kernel(new Container($config, $this->db, $this->clock, $failing, $this->notifier, $this->push));

        $res = $this->call('POST', '/v1/auth/code', ['phone' => '+79161234567']);
        $this->assertSame(503, $res['status']);
        $this->assertSame('sms_unavailable', $res['body']['error']['code']);
    }

    public function testOversizedBodyIs413(): void
    {
        $res = $this->call('POST', '/v1/cart/quote', null, null, [], str_repeat(' ', 70000));

        $this->assertSame(413, $res['status']);
    }

    public function testBasePathMustMatchWholeSegment(): void
    {
        $this->kernel = $this->buildKernel(['API_BASE_PATH' => '/api']);

        $this->assertSame(200, $this->call('GET', '/api/v1/home')['status']);
        $this->assertSame(404, $this->call('GET', '/apix/v1/home')['status']);
    }

    public function testIdempotencyKeyCannotBeReusedForAnotherKind(): void
    {
        $s = $this->login();
        $this->call('POST', '/v1/requests', ['kind' => 'callback'], $s['token'], ['Idempotency-Key' => 'same-key-001']);

        $res = $this->call('POST', '/v1/orders', [
            'items' => [['productId' => 7138, 'complectId' => 1724, 'qty' => 1]],
            'eventDate' => '2026-11-01', 'delivery' => ['method' => 'pickup'],
        ], $s['token'], ['Idempotency-Key' => 'same-key-001']);

        $this->assertSame(422, $res['status']);
        $this->assertSame('idempotency_key_reused', $res['body']['error']['code']);
    }

    public function testRequestRejectsNonIntegerIds(): void
    {
        $s = $this->login();
        $res = $this->call('POST', '/v1/requests', ['kind' => 'product', 'productId' => ['x' => str_repeat('a', 100)]], $s['token'], ['Idempotency-Key' => 'req-bad-0001']);

        $this->assertSame(422, $res['status']);
        $this->assertArrayHasKey('productId', $res['body']['error']['fields']);
    }

    public function testCustomerCancelNotifiesManagersAndCannotTouchOthers(): void
    {
        $owner = $this->login('+79161111111');
        $other = $this->login('+79162222222');
        $id = $this->call('POST', '/v1/requests', ['kind' => 'callback'], $owner['token'], ['Idempotency-Key' => 'req-own-0001'])['body']['data']['id'];

        $this->assertSame(404, $this->call('POST', "/v1/orders/{$id}/cancel", null, $other['token'])['status']);
        $this->assertSame(200, $this->call('POST', "/v1/orders/{$id}/cancel", null, $owner['token'])['status']);
        $this->assertCount(1, $this->notifier->cancelled);
    }

    public function testResponsesOmitNullFields(): void
    {
        $s = $this->login();
        $order = $this->call('POST', '/v1/requests', ['kind' => 'callback'], $s['token'], ['Idempotency-Key' => 'req-null-001'])['body']['data'];

        $this->assertArrayNotHasKey('eventDate', $order);
        $this->assertArrayNotHasKey('delivery', $order);
        $this->assertNotContains(null, $order, 'на верхнем уровне нет null');
    }
}
