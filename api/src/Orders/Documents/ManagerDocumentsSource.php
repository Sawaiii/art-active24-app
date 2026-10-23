<?php

declare(strict_types=1);

namespace App\Orders\Documents;

use App\Db\Database;
use App\Http\HttpError;
use App\Support\Clock;
use App\Support\Time;

/**
 * Ссылки на документы, приложенные менеджером (договор, счёт, КП в облаке). Только https.
 */
final class ManagerDocumentsSource implements OrderDocumentsSource
{
    public const KINDS = ['contract', 'act', 'invoice', 'kp', 'other'];

    public function __construct(
        private readonly Database $db,
        private readonly Clock $clock,
    ) {
    }

    public function documents(array $order): array
    {
        return array_map(
            self::present(...),
            $this->db->all('SELECT * FROM app_order_documents WHERE order_id = ? ORDER BY id DESC', [(int) $order['id']]),
        );
    }

    /**
     * @param array<string, mixed> $body DocumentInput
     * @return array<string, mixed> OrderDocument
     */
    public function add(int $orderId, array $body, int $managerId): array
    {
        $errors = [];
        $title = is_string($body['title'] ?? null) ? trim($body['title']) : '';
        if ($title === '' || mb_strlen($title) > 200) {
            $errors['title'] = 'Название — от 1 до 200 символов';
        }
        $kind = $body['kind'] ?? null;
        if (!in_array($kind, self::KINDS, true)) {
            $errors['kind'] = 'Тип: contract, act, invoice, kp или other';
        }
        $url = is_string($body['url'] ?? null) ? trim($body['url']) : '';
        if (strlen($url) > 1000 || filter_var($url, FILTER_VALIDATE_URL) === false || strtolower((string) parse_url($url, PHP_URL_SCHEME)) !== 'https') {
            $errors['url'] = 'Ссылка https:// до 1000 символов';
        }
        $date = $body['date'] ?? null;
        if ($date !== null && (!is_string($date) || ($d = \DateTimeImmutable::createFromFormat('!Y-m-d', $date)) === false || $d->format('Y-m-d') !== $date)) {
            $errors['date'] = 'Дата в формате ГГГГ-ММ-ДД';
        }
        $size = $body['size'] ?? null;
        if ($size !== null && (!is_int($size) || $size < 0)) {
            $errors['size'] = 'Размер — целое число байт';
        }
        $mime = $body['mime'] ?? null;
        if ($mime !== null && (!is_string($mime) || !preg_match('~^[\w.+-]{1,50}/[\w.+-]{1,49}$~', $mime))) {
            $errors['mime'] = 'MIME-тип вида application/pdf';
        }
        if ($errors !== []) {
            throw HttpError::validation($errors);
        }
        $id = $this->db->insert('app_order_documents', [
            'order_id' => $orderId,
            'title' => $title,
            'kind' => $kind,
            'url' => $url,
            'mime' => $mime,
            'size' => $size,
            'doc_date' => $date,
            'created_by' => $managerId,
            'created_at' => Time::toDb($this->clock->now()),
        ]);
        return self::present($this->db->one('SELECT * FROM app_order_documents WHERE id = ?', [$id]) ?? []);
    }

    public function delete(int $orderId, string $docId): void
    {
        if (!preg_match('/^m-(\d{1,10})$/', $docId, $m)
            || $this->db->run('DELETE FROM app_order_documents WHERE id = ? AND order_id = ?', [(int) $m[1], $orderId])->rowCount() !== 1) {
            throw HttpError::notFound('Документ');
        }
    }

    /**
     * @param array<string, mixed> $row
     * @return array<string, mixed>
     */
    private static function present(array $row): array
    {
        return [
            'id' => 'm-' . $row['id'],
            'title' => (string) $row['title'],
            'kind' => (string) $row['kind'],
            'source' => 'manager',
            'date' => $row['doc_date'] ?? substr((string) $row['created_at'], 0, 10),
            'url' => (string) $row['url'],
            'size' => $row['size'] === null ? null : (int) $row['size'],
            'mime' => $row['mime'],
        ];
    }
}
