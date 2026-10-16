<?php

declare(strict_types=1);

namespace App\Orders;

use App\Support\Logger;

/**
 * Письма менеджерам о заявках через mail() сервера сайта.
 * Заголовки собираются только из конфигурации и номера заявки — пользовательский текст идёт лишь в тело.
 */
final class MailOrderNotifier implements OrderNotifier
{
    /** @param list<string> $recipients */
    public function __construct(
        private readonly array $recipients,
        private readonly string $from,
        private readonly Logger $logger,
    ) {
    }

    public function orderCreated(array $order): void
    {
        $this->send("Заявка {$order['number']} из приложения", OrderText::summary($order), (string) $order['number']);
    }

    public function orderCancelled(array $order): void
    {
        $this->send(
            "Заявка {$order['number']} отменена клиентом",
            "Клиент отменил заявку в приложении.\n\n" . OrderText::summary($order),
            (string) $order['number'],
        );
    }

    private function send(string $subject, string $body, string $number): void
    {
        if ($this->recipients === []) {
            return;
        }
        $headers = implode("\r\n", [
            'From: ' . $this->from,
            'MIME-Version: 1.0',
            'Content-Type: text/plain; charset=UTF-8',
            'Content-Transfer-Encoding: 8bit',
        ]);
        $encodedSubject = '=?UTF-8?B?' . base64_encode($subject) . '?=';
        if (!mail(implode(', ', $this->recipients), $encodedSubject, $body, $headers)) {
            $this->logger->error('Не удалось отправить письмо о заявке', ['order' => $number]);
        }
    }
}
