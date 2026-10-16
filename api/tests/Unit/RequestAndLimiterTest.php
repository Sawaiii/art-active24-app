<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Db\Database;
use App\Db\Migrator;
use App\Http\HttpError;
use App\Http\Request;
use App\Support\FrozenClock;
use App\Support\RateLimiter;
use PHPUnit\Framework\TestCase;

final class RequestAndLimiterTest extends TestCase
{
    public function testForwardedForIsIgnoredFromUntrustedPeer(): void
    {
        $this->assertSame('203.0.113.9', Request::clientIp('203.0.113.9', '1.2.3.4', ['127.0.0.1']));
    }

    public function testForwardedForTakesRightmostNonProxyAddress(): void
    {
        $ip = Request::clientIp('127.0.0.1', '6.6.6.6, 198.51.100.7, 10.0.0.2', ['127.0.0.1', '10.0.0.2']);

        $this->assertSame('198.51.100.7', $ip, 'подделанный левый адрес клиента игнорируется');
    }

    public function testIpv6IsBucketedBySlash64(): void
    {
        $this->assertSame(
            RateLimiter::ipBucket('2001:db8:1:2::1'),
            RateLimiter::ipBucket('2001:db8:1:2:ffff:ffff:ffff:ffff'),
        );
        $this->assertSame('192.0.2.1', RateLimiter::ipBucket('192.0.2.1'));
    }

    public function testLimiterBlocksAfterLimitAndResetsAfterWindow(): void
    {
        $db = Database::connect('sqlite::memory:');
        (new Migrator($db, dirname(__DIR__, 2) . '/migrations'))->migrate();
        $clock = new FrozenClock();
        $limiter = new RateLimiter($db, $clock);

        $limiter->hit('b', 2, 60);
        $limiter->hit('b', 2, 60);
        try {
            $limiter->hit('b', 2, 60);
            $this->fail('третий запрос в окне должен быть отклонён');
        } catch (HttpError $e) {
            $this->assertSame(429, $e->status);
            $this->assertSame(60, $e->retryAfter);
        }

        $clock->advance(61);
        $limiter->hit('b', 2, 60);
        $this->addToAssertionCount(1);
    }
}
