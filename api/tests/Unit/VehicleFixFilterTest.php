<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Orders\Vehicle\VehicleFix;
use App\Orders\Vehicle\VehicleFixFilter;
use PHPUnit\Framework\TestCase;

final class VehicleFixFilterTest extends TestCase
{
    private VehicleFixFilter $filter;
    private \DateTimeImmutable $now;

    protected function setUp(): void
    {
        $this->filter = new VehicleFixFilter();
        $this->now = new \DateTimeImmutable('2026-10-16 12:00:00', new \DateTimeZone('UTC'));
    }

    private function fix(float $lat, float $lng, float $accuracy = 20, int $secondsAgo = 0): VehicleFix
    {
        return new VehicleFix($lat, $lng, $accuracy, $this->now->modify("-{$secondsAgo} seconds"));
    }

    public function testNormalDrivingIsAccepted(): void
    {
        // ~1 км за 60 с = 60 км/ч
        $previous = $this->fix(55.7558, 37.6173, 20, 60);
        $this->assertNull($this->filter->reject($this->fix(55.7648, 37.6173), $previous, $this->now));
        $this->assertNull($this->filter->reject($this->fix(55.7558, 37.6173), null, $this->now), 'первая точка');
    }

    public function testRejectsLowAccuracy(): void
    {
        $this->assertSame('low_accuracy', $this->filter->reject($this->fix(55.75, 37.61, 501), null, $this->now));
        $this->assertNull($this->filter->reject($this->fix(55.75, 37.61, 500), null, $this->now));
    }

    public function testRejectsJumpFasterThan150KmH(): void
    {
        // 10 км за 60 с = 600 км/ч
        $previous = $this->fix(55.7558, 37.6173, 20, 60);
        $this->assertSame('implausible_speed', $this->filter->reject($this->fix(55.8458, 37.6173), $previous, $this->now));
    }

    public function testJitterWithinAccuracyIsNotAJump(): void
    {
        // 300 м за 1 с, но радиусы точности 200 + 150 м: машина стоит, GPS «дрожит».
        $previous = $this->fix(55.7558, 37.6173, 200, 1);
        $this->assertNull($this->filter->reject($this->fix(55.7585, 37.6173, 150), $previous, $this->now));
    }

    public function testRejectsOutsideMoscowRegion(): void
    {
        $this->assertSame('out_of_region', $this->filter->reject($this->fix(59.9386, 30.3141), null, $this->now), 'Санкт-Петербург');
        $this->assertSame('out_of_region', $this->filter->reject($this->fix(0.0, 0.0), null, $this->now), 'нулевой остров');
        $this->assertNull($this->filter->reject($this->fix(55.4319, 37.5450), null, $this->now), 'Подольск — область');
    }

    public function testRejectsKnownSpoofPointUnlessCarWasNearby(): void
    {
        $vnukovo = $this->fix(55.5918, 37.2610);
        $this->assertSame('spoof_point', $this->filter->reject($vnukovo, null, $this->now));
        $fromKremlin = $this->fix(55.7520, 37.6175, 20, 600);
        $this->assertSame('spoof_point', $this->filter->reject($vnukovo, $fromKremlin, $this->now));
        $nearAirport = $this->fix(55.6100, 37.2900, 20, 120);
        $this->assertNull($this->filter->reject($vnukovo, $nearAirport, $this->now), 'заказ правда едет во Внуково');
    }

    public function testRejectsOutOfOrderAndFutureFixes(): void
    {
        $previous = $this->fix(55.75, 37.61, 20, 10);
        $this->assertSame('stale', $this->filter->reject($this->fix(55.75, 37.61, 20, 30), $previous, $this->now));
        $future = new VehicleFix(55.75, 37.61, 20, $this->now->modify('+10 minutes'));
        $this->assertSame('clock_skew', $this->filter->reject($future, null, $this->now));
    }

    public function testConfigParsing(): void
    {
        $this->assertSame([55.0, 36.0, 56.0, 38.0], VehicleFixFilter::parseRegion('55, 36, 56, 38'));
        $this->assertSame(VehicleFixFilter::MOSCOW_REGION, VehicleFixFilter::parseRegion(null));
        $this->assertSame([[55.5, 37.2], [55.9, 37.4]], VehicleFixFilter::parsePoints('55.5,37.2; 55.9,37.4'));
        $this->assertSame([], VehicleFixFilter::parsePoints('-'));
        $this->expectException(\RuntimeException::class);
        VehicleFixFilter::parseRegion('56,36,55,38');
    }
}
