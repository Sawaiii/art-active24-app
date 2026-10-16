<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Catalog\Snapshot\ColorPalette;
use PHPUnit\Framework\TestCase;

final class ColorPaletteTest extends TestCase
{
    public function testSpellingAndWordFormVariantsShareOneName(): void
    {
        $this->assertSame('Черный', ColorPalette::canonical('Чёрный'));
        $this->assertSame('Черный', ColorPalette::canonical('черный '));
        $this->assertSame('Золотой', ColorPalette::canonical('Золото'));
        $this->assertSame('Золотой', ColorPalette::canonical('Золотой'));
        $this->assertSame('Серебряный', ColorPalette::canonical('Серебро'));
        $this->assertSame('Белый', ColorPalette::canonical('Белая'));
        $this->assertSame('Синий', ColorPalette::canonical('синяя'));
        $this->assertSame('Золотой', ColorPalette::canonical('Золотые'));
    }

    public function testUnknownColorKeepsItsOwnName(): void
    {
        $this->assertSame('Мятный', ColorPalette::canonical('мятный'));
        $this->assertNull(ColorPalette::hex('Мятный'));
    }
}
