<?php

declare(strict_types=1);

namespace App\Auth;

/**
 * Отправка через sms.ru (HTTP API). Ключ — SMSRU_API_ID в окружении.
 */
final class SmsRuSender implements SmsSender
{
    private const ENDPOINT = 'https://sms.ru/sms/send';

    public function __construct(
        private readonly string $apiId,
        private readonly ?string $from = null,
    ) {
    }

    public function send(PhoneNumber $phone, string $text): void
    {
        $params = ['api_id' => $this->apiId, 'to' => ltrim($phone->value, '+'), 'msg' => $text, 'json' => 1];
        if ($this->from !== null) {
            $params['from'] = $this->from;
        }
        $ch = curl_init(self::ENDPOINT);
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => http_build_query($params),
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 10,
        ]);
        $body = curl_exec($ch);
        $error = curl_error($ch);
        curl_close($ch);

        if ($body === false) {
            throw new \RuntimeException("sms.ru недоступен: {$error}");
        }
        $data = json_decode((string) $body, true);
        $status = $data['sms'][ltrim($phone->value, '+')]['status'] ?? null;
        if (($data['status'] ?? null) !== 'OK' || $status !== 'OK') {
            throw new \RuntimeException('sms.ru отклонил сообщение: ' . substr((string) $body, 0, 300));
        }
    }
}
