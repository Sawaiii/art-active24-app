<?php

declare(strict_types=1);

namespace Tests\Integration;

final class AuthFlowTest extends ApiTestCase
{
    public function testLoginCreatesCustomerAndMeWorks(): void
    {
        $session = $this->login('8 (916) 123-45-67');

        $this->assertSame('+79161234567', $session['user']['phone']);
        $this->assertSame('customer', $session['user']['role']);
        $me = $this->call('GET', '/v1/me', null, $session['token']);
        $this->assertSame(200, $me['status']);
    }

    public function testWrongCodeIsRejectedAndAttemptsAreLimited(): void
    {
        $this->call('POST', '/v1/auth/code', ['phone' => '+79161234567']);
        preg_match('/(\d{6})/', (string) $this->sms->lastTextFor('+79161234567'), $m);
        $wrong = str_pad((string) (((int) $m[1] + 1) % 1000000), 6, '0', STR_PAD_LEFT);
        for ($i = 0; $i < 5; $i++) {
            $res = $this->call('POST', '/v1/auth/verify', ['phone' => '+79161234567', 'code' => $wrong]);
            $this->assertSame(422, $res['status']);
        }
        $blocked = $this->call('POST', '/v1/auth/verify', ['phone' => '+79161234567', 'code' => $m[1]]);
        $this->assertSame(422, $blocked['status'], 'после 5 ошибок верный код уже не принимается');
    }

    public function testResendTooEarlyIsRateLimited(): void
    {
        $this->assertSame(200, $this->call('POST', '/v1/auth/code', ['phone' => '+79161234567'])['status']);
        $second = $this->call('POST', '/v1/auth/code', ['phone' => '+79161234567']);
        $this->assertSame(429, $second['status']);

        $this->clock->advance(61);
        $this->assertSame(200, $this->call('POST', '/v1/auth/code', ['phone' => '+79161234567'])['status']);
    }

    public function testExpiredCodeIsRejected(): void
    {
        $this->call('POST', '/v1/auth/code', ['phone' => '+79161234567']);
        preg_match('/(\d{6})/', (string) $this->sms->lastTextFor('+79161234567'), $m);
        $this->clock->advance(301);

        $this->assertSame(422, $this->call('POST', '/v1/auth/verify', ['phone' => '+79161234567', 'code' => $m[1]])['status']);
    }

    public function testInvalidPhoneIsValidationError(): void
    {
        $res = $this->call('POST', '/v1/auth/code', ['phone' => '12345']);

        $this->assertSame(422, $res['status']);
        $this->assertArrayHasKey('phone', $res['body']['error']['fields']);
    }

    public function testRefreshRotatesTokensAndOldRefreshDies(): void
    {
        $session = $this->login();
        $refreshed = $this->call('POST', '/v1/auth/refresh', ['refreshToken' => $session['refresh']]);
        $this->assertSame(200, $refreshed['status']);

        $this->assertSame(401, $this->call('POST', '/v1/auth/refresh', ['refreshToken' => $session['refresh']])['status']);
        $this->assertSame(401, $this->call('GET', '/v1/me', null, $session['token'])['status']);
        $this->assertSame(200, $this->call('GET', '/v1/me', null, $refreshed['body']['data']['accessToken'])['status']);
    }

    public function testAccessTokenExpires(): void
    {
        $session = $this->login();
        $this->clock->advance(1801);

        $res = $this->call('GET', '/v1/me', null, $session['token']);
        $this->assertSame(401, $res['status']);
        $this->assertSame('token_expired', $res['body']['error']['code']);
    }

    public function testLogoutRevokesSession(): void
    {
        $session = $this->login();
        $this->assertSame(204, $this->call('POST', '/v1/auth/logout', null, $session['token'])['status']);

        $this->assertSame(401, $this->call('GET', '/v1/me', null, $session['token'])['status']);
    }

    public function testManagerPhoneGetsManagerRole(): void
    {
        $this->assertSame('manager', $this->login(self::MANAGER_PHONE)['user']['role']);
    }

    public function testProfileUpdateValidatesEmail(): void
    {
        $session = $this->login();

        $bad = $this->call('PATCH', '/v1/me', ['email' => 'not-an-email'], $session['token']);
        $this->assertSame(422, $bad['status']);

        $ok = $this->call('PATCH', '/v1/me', ['name' => 'Анна', 'email' => 'anna@example.com'], $session['token']);
        $this->assertSame('Анна', $ok['body']['data']['name']);
    }
}
