<?php

declare(strict_types=1);

namespace Tests\Integration;

use App\Auth\LogSmsSender;
use App\Config;
use App\Container;
use App\Db\Database;
use App\Db\Migrator;
use App\Http\Request;
use App\Kernel;
use App\Orders\LogOrderNotifier;
use App\Push\LogPushSender;
use App\Support\FrozenClock;
use App\Support\Logger;
use PHPUnit\Framework\TestCase;

/**
 * Полный HTTP-путь через Kernel на SQLite в памяти и снапшоте-фикстуре.
 */
abstract class ApiTestCase extends TestCase
{
    protected const MANAGER_PHONE = '+79990000001';

    protected FrozenClock $clock;
    protected LogSmsSender $sms;
    protected LogOrderNotifier $notifier;
    protected LogPushSender $push;
    protected Kernel $kernel;
    protected Database $db;

    protected function setUp(): void
    {
        $root = dirname(__DIR__, 2);
        $this->db = Database::connect('sqlite::memory:');
        (new Migrator($this->db, $root . '/migrations'))->migrate();

        $this->clock = new FrozenClock('2026-10-16 09:00:00');
        $this->sms = new LogSmsSender();
        $this->notifier = new LogOrderNotifier(new Logger(null));
        $this->push = new LogPushSender(new Logger(null));

        $this->kernel = $this->buildKernel([]);
    }

    /**
     * Kernel поверх той же БД и часов — для проверки смены конфигурации «на лету».
     *
     * @param array<string, string> $override
     */
    protected function buildKernel(array $override): Kernel
    {
        $config = Config::fromArray($override + [
            'APP_ENV' => 'test',
            'LOG_FILE' => 'off',
            'SNAPSHOT_DIR' => dirname(__DIR__, 2) . '/tests/fixtures/snapshot',
            'AUTH_PEPPER' => str_repeat('p', 40),
            'MANAGER_PHONES' => self::MANAGER_PHONE,
        ]);
        return new Kernel(new Container($config, $this->db, $this->clock, $this->sms, $this->notifier, $this->push));
    }

    /**
     * @param array<string, mixed>|null $body
     * @param array<string, string> $headers
     * @return array{status: int, body: array<string, mixed>}
     */
    protected function call(string $method, string $uri, ?array $body = null, ?string $token = null, array $headers = [], ?string $rawBody = null): array
    {
        $path = (string) parse_url($uri, PHP_URL_PATH);
        parse_str((string) parse_url($uri, PHP_URL_QUERY), $query);
        $lower = array_change_key_case($headers);
        if ($token !== null) {
            $lower['authorization'] = 'Bearer ' . $token;
        }
        $request = new Request(
            $method,
            $path,
            array_map('strval', $query),
            $lower,
            $rawBody ?? ($body === null ? '' : json_encode($body, JSON_THROW_ON_ERROR)),
            '127.0.0.1',
        );
        $response = $this->kernel->handle($request);
        return ['status' => $response->status, 'body' => $response->body];
    }

    /** @return array{token: string, refresh: string, user: array<string, mixed>} */
    protected function login(string $phone = '+79161234567'): array
    {
        $this->call('POST', '/v1/auth/code', ['phone' => $phone]);
        $canonical = \App\Auth\PhoneNumber::parse($phone)->value;
        preg_match('/(\d{6})/', (string) $this->sms->lastTextFor($canonical), $m);
        $res = $this->call('POST', '/v1/auth/verify', ['phone' => $phone, 'code' => $m[1]]);
        $this->assertSame(200, $res['status'], json_encode($res['body'], JSON_UNESCAPED_UNICODE));
        $this->clock->advance(61);
        return [
            'token' => $res['body']['data']['accessToken'],
            'refresh' => $res['body']['data']['refreshToken'],
            'user' => $res['body']['data']['user'],
        ];
    }
}
