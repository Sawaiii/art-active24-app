<?php

declare(strict_types=1);

namespace App\Auth;

/**
 * Отправка SMS. Реализации: LogSmsSender (разработка), SmsRuSender (sms.ru, прод).
 */
interface SmsSender
{
    /** @throws \RuntimeException если провайдер не принял сообщение */
    public function send(PhoneNumber $phone, string $text): void;
}
