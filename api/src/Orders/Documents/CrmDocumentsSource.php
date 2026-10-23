<?php

declare(strict_types=1);

namespace App\Orders\Documents;

/**
 * Документы сделки из CRM («Программа КП» / Tony). Выключено по умолчанию.
 *
 * Сейчас (CRM_DOCUMENTS_ENABLED=true + CRM_ACT_URL_TEMPLATE, например
 * https://crm.apihide.com/orders/orders_act/?id=<ORDERID> — тот же шаблон, что TONY_ACT_URL в Вызов Чате)
 * отдаёт ссылку на акт сделки. Важно: страница CRM должна открываться клиенту без входа в CRM
 * (публичная подписанная ссылка) — иначе не включать.
 *
 * Что сделать дальше: когда будет API CRM — список файлов сделки (договор, счёт, КП) с их датами
 * и размерами вместо одного шаблона.
 */
final class CrmDocumentsSource implements OrderDocumentsSource
{
    public function __construct(
        private readonly bool $enabled,
        private readonly ?string $actUrlTemplate,
    ) {
    }

    public function documents(array $order): array
    {
        $deal = $order['crmDealId'] ?? null;
        if (!$this->enabled || $this->actUrlTemplate === null || !is_string($deal) || $deal === '') {
            return [];
        }
        return [[
            'id' => 'crm-act',
            'title' => "Акт по сделке {$deal}",
            'kind' => 'act',
            'source' => 'crm',
            'url' => str_replace('<ORDERID>', rawurlencode($deal), $this->actUrlTemplate),
        ]];
    }
}
