<?php

declare(strict_types=1);

namespace App\Auth;

/**
 * Для разработки: SMS пишутся в файл, а не отправляются. В production запрещён (см. Container).
 */
final class LogSmsSender implements SmsSender
{
    /** @var list<array{phone: string, text: string}> */
    private array $sent = [];

    public function __construct(private readonly ?string $logFile = null)
    {
    }

    public function send(PhoneNumber $phone, string $text): void
    {
        $this->sent[] = ['phone' => $phone->value, 'text' => $text];
        if ($this->logFile !== null) {
            file_put_contents($this->logFile, gmdate('c') . " {$phone->value} {$text}\n", FILE_APPEND | LOCK_EX);
        }
    }

    public function lastTextFor(string $phone): ?string
    {
        foreach (array_reverse($this->sent) as $message) {
            if ($message['phone'] === $phone) {
                return $message['text'];
            }
        }
        return null;
    }
}
