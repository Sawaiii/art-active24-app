<?php

declare(strict_types=1);

namespace App;

use App\Auth\LogSmsSender;
use App\Auth\ManagerPolicy;
use App\Auth\PhoneNumber;
use App\Auth\OtpService;
use App\Auth\SessionService;
use App\Auth\SmsRuSender;
use App\Auth\SmsSender;
use App\Cart\CartRepository;
use App\Cart\QuoteService;
use App\Catalog\CatalogRepository;
use App\Catalog\ContentRepository;
use App\Catalog\Snapshot\SnapshotCatalogRepository;
use App\Catalog\Snapshot\SnapshotContentRepository;
use App\Catalog\Snapshot\SnapshotStore;
use App\Catalog\Snapshot\SnapshotVenueRepository;
use App\Catalog\VenueRepository;
use App\Db\Database;
use App\Integrations\VyzovChat\StubVyzovChatGateway;
use App\Integrations\VyzovChat\VyzovChatGateway;
use App\Loyalty\LoyaltyService;
use App\Loyalty\LoyaltyTiers;
use App\Orders\Composition\CartCompositionSource;
use App\Orders\Composition\CompositionNormalizer;
use App\Orders\Composition\CompositionService;
use App\Orders\Composition\HttpKpClient;
use App\Orders\Composition\KpCompositionSource;
use App\Orders\Composition\ManagerCompositionSource;
use App\Orders\Documents\CompositeDocumentsSource;
use App\Orders\Documents\CrmDocumentsSource;
use App\Orders\Documents\ManagerDocumentsSource;
use App\Orders\Documents\OrderDocumentsSource;
use App\Orders\Documents\VyzovChatDocumentsSource;
use App\Orders\Feedback\ClaimService;
use App\Orders\Feedback\FeedbackRepository;
use App\Orders\Feedback\ReviewService;
use App\Orders\Vehicle\DriverPhoneLocationSource;
use App\Orders\Vehicle\GpsTrackerLocationSource;
use App\Orders\Vehicle\StubTrackerClient;
use App\Orders\Vehicle\VehicleFixFilter;
use App\Orders\Vehicle\VehicleRepository;
use App\Orders\Vehicle\VehicleService;
use App\Orders\LogOrderNotifier;
use App\Orders\MailOrderNotifier;
use App\Orders\OrderNotifier;
use App\Orders\OrderPresenter;
use App\Orders\OrderRepository;
use App\Orders\OrderService;
use App\Pricing\PriceCalculator;
use App\Push\DeviceRepository;
use App\Push\LogPushSender;
use App\Push\PushSender;
use App\Support\Clock;
use App\Support\Logger;
use App\Support\RateLimiter;
use App\Support\SystemClock;
use App\Users\FavoriteRepository;
use App\Users\UserRepository;

/**
 * Сборка зависимостей из конфигурации. Явная, без магии: каждый сервис создаётся один раз.
 */
final class Container
{
    public readonly Clock $clock;
    public readonly Logger $logger;
    public readonly Database $db;
    public readonly CatalogRepository $catalog;
    public readonly VenueRepository $venues;
    public readonly ContentRepository $content;
    public readonly SmsSender $sms;
    public readonly OrderNotifier $notifier;
    public readonly PushSender $push;
    public readonly RateLimiter $limiter;
    public readonly UserRepository $users;
    public readonly ManagerPolicy $managers;
    public readonly SessionService $sessions;
    public readonly OtpService $otp;
    public readonly QuoteService $quotes;
    public readonly CartRepository $carts;
    public readonly FavoriteRepository $favorites;
    public readonly DeviceRepository $devices;
    public readonly OrderService $orders;
    public readonly LoyaltyService $loyalty;
    public readonly VyzovChatGateway $vyzovChat;
    public readonly CompositionService $composition;
    public readonly ManagerCompositionSource $managerComposition;
    public readonly VehicleService $vehicles;
    public readonly ReviewService $reviews;
    public readonly ClaimService $claims;
    public readonly ManagerDocumentsSource $managerDocuments;
    public readonly OrderDocumentsSource $documents;

    public function __construct(
        public readonly Config $config,
        ?Database $db = null,
        ?Clock $clock = null,
        ?SmsSender $sms = null,
        ?OrderNotifier $notifier = null,
        ?PushSender $push = null,
    ) {
        $root = dirname(__DIR__);
        $this->clock = $clock ?? new SystemClock();
        $logFile = $config->get('LOG_FILE', $root . '/var/log/app.log');
        $this->logger = new Logger($logFile === 'off' ? null : $logFile);
        $this->db = $db ?? Database::connect(
            Database::resolveDsn($config->get('DB_DSN', 'sqlite:var/app.sqlite') ?? '', $root),
            $config->get('DB_USER'),
            $config->get('DB_PASSWORD'),
        );

        [$this->catalog, $this->venues, $this->content] = $this->catalogSource($config, $root);
        $this->sms = $sms ?? $this->smsSender($config, $root);
        $this->notifier = $notifier ?? $this->orderNotifier($config);
        $this->push = $push ?? new LogPushSender($this->logger);

        $this->limiter = new RateLimiter($this->db, $this->clock);
        $this->users = new UserRepository($this->db, $this->clock);
        [$reviewPhone, $reviewCode] = $this->reviewLogin($config);
        $this->managers = new ManagerPolicy($config->list('MANAGER_PHONES'), $reviewPhone);
        $this->sessions = new SessionService($this->db, $this->clock);
        $this->otp = new OtpService(
            $this->db, $this->sms, $this->limiter, $this->clock, $this->logger,
            $this->pepper($config), $reviewPhone, $reviewCode,
        );
        $this->quotes = new QuoteService($this->catalog, new PriceCalculator());
        $this->carts = new CartRepository($this->db, $this->clock);
        $this->favorites = new FavoriteRepository($this->db, $this->clock);
        $this->devices = new DeviceRepository($this->db, $this->clock);
        $this->loyalty = new LoyaltyService($this->db, $this->loyaltyTiers($config, $root), $config->bool('LOYALTY_ENABLED', true));
        $orderRepository = new OrderRepository($this->db, $this->clock);
        $feedback = new FeedbackRepository($this->db, $this->clock);
        $this->orders = new OrderService(
            $orderRepository, new OrderPresenter($orderRepository, $feedback, $this->clock), $this->quotes, $this->carts,
            $this->catalog, $this->venues, $this->notifier, $this->push, $this->limiter, $this->logger, $this->clock,
            $this->loyalty,
        );
        $this->cabinet($config, $orderRepository, $feedback);
    }

    /** Личный кабинет заказа: состав, машина, отзыв, претензии, документы и их внешние источники. */
    private function cabinet(Config $config, OrderRepository $orders, FeedbackRepository $feedback): void
    {
        $vyzovChatUrl = $config->get('VYZOVCHAT_BASE_URL', 'https://vyzovchat.ru') ?? 'https://vyzovchat.ru';
        $this->vyzovChat = new StubVyzovChatGateway(
            $vyzovChatUrl,
            $config->bool('VYZOVCHAT_ENABLED', false) && $config->get('VYZOVCHAT_API_TOKEN') !== null,
        );

        $normalizer = new CompositionNormalizer();
        $this->managerComposition = new ManagerCompositionSource($this->db, $this->clock);
        $kp = new HttpKpClient($config->bool('KP_SOURCE_ENABLED', false), $config->get('KP_API_URL'), $config->get('KP_API_TOKEN'));
        $this->composition = new CompositionService(
            [new KpCompositionSource($kp, $normalizer), $this->managerComposition, new CartCompositionSource($this->catalog)],
            $this->managerComposition,
            $normalizer,
            $this->logger,
        );

        $tracker = $config->get('VEHICLE_TRACKER', 'none') ?? 'none';
        if (!in_array($tracker, ['none', 'traccar', 'wialon'], true)) {
            throw new \RuntimeException('VEHICLE_TRACKER: none | traccar | wialon');
        }
        $filter = new VehicleFixFilter(
            VehicleFixFilter::parseRegion($config->get('VEHICLE_REGION_BBOX')),
            VehicleFixFilter::parsePoints($config->get('VEHICLE_SPOOF_POINTS')),
        );
        $clock = $this->clock;
        $this->vehicles = new VehicleService(
            $orders,
            new VehicleRepository($this->db, $this->clock),
            [new DriverPhoneLocationSource(), new GpsTrackerLocationSource(new StubTrackerClient($tracker), $filter, static fn () => $clock->now())],
            $filter,
            $this->clock,
            $this->logger,
            $config->int('VEHICLE_STALE_SECONDS', 600),
            $config->int('DRIVER_TOKEN_TTL_HOURS', 48),
        );

        $this->reviews = new ReviewService($feedback, $this->vyzovChat, $this->clock, $this->logger);
        $this->claims = new ClaimService(
            $feedback, $orders, $this->vyzovChat, $this->push, $this->limiter, $this->clock, $this->logger, $vyzovChatUrl,
        );
        $this->managerDocuments = new ManagerDocumentsSource($this->db, $this->clock);
        $this->documents = new CompositeDocumentsSource([
            $this->managerDocuments,
            new CrmDocumentsSource($config->bool('CRM_DOCUMENTS_ENABLED', false), $config->get('CRM_ACT_URL_TEMPLATE')),
            new VyzovChatDocumentsSource($this->vyzovChat),
        ], $this->logger);
    }

    private function loyaltyTiers(Config $config, string $root): LoyaltyTiers
    {
        $json = $config->get('LOYALTY_TIERS');
        $file = $config->get('LOYALTY_TIERS_FILE');
        if ($json === null && $file !== null) {
            $path = str_starts_with($file, '/') || preg_match('~^[A-Za-z]:[\\\\/]~', $file) === 1 ? $file : $root . '/' . $file;
            $json = is_file($path) ? (string) file_get_contents($path) : throw new \RuntimeException("LOYALTY_TIERS_FILE: нет файла {$file}");
        }
        return $json === null ? LoyaltyTiers::default() : LoyaltyTiers::fromJson($json);
    }

    private function pepper(Config $config): string
    {
        $pepper = $config->require('AUTH_PEPPER');
        if (strlen($pepper) < 32 || str_contains($pepper, 'change-me')) {
            throw new \RuntimeException('AUTH_PEPPER должен быть случайной строкой не короче 32 символов');
        }
        return $pepper;
    }

    /**
     * Демо-вход для ревью магазинов приложений: оба значения или ни одного, код — по длине SMS-кода.
     *
     * @return array{0: ?string, 1: ?string}
     */
    private function reviewLogin(Config $config): array
    {
        $phone = $config->get('AUTH_REVIEW_PHONE');
        $code = $config->get('AUTH_REVIEW_CODE');
        if ($phone === null && $code === null) {
            return [null, null];
        }
        if ($phone === null || $code === null || !preg_match('/^\d{' . OtpService::CODE_LENGTH . '}$/', $code)) {
            throw new \RuntimeException('AUTH_REVIEW_PHONE и AUTH_REVIEW_CODE (' . OtpService::CODE_LENGTH . ' цифр) задаются вместе');
        }
        return [PhoneNumber::parse($phone, 'AUTH_REVIEW_PHONE')->value, $code];
    }

    /** @return array{0: CatalogRepository, 1: VenueRepository, 2: ContentRepository} */
    private function catalogSource(Config $config, string $root): array
    {
        $source = $config->get('CATALOG_SOURCE', 'snapshot');
        if ($source !== 'snapshot') {
            // MysqlCatalogRepository появится вместе со схемой БД CMS (см. docs/DATA-MODEL.md).
            throw new \RuntimeException("Источник каталога «{$source}» не поддерживается");
        }
        $store = new SnapshotStore($config->get('SNAPSHOT_DIR', $root . '/data/snapshot') ?? '');
        $catalog = new SnapshotCatalogRepository($store);
        return [$catalog, new SnapshotVenueRepository($store), new SnapshotContentRepository($store, $catalog)];
    }

    private function smsSender(Config $config, string $root): SmsSender
    {
        $provider = $config->get('SMS_PROVIDER', 'log');
        if ($provider === 'smsru') {
            return new SmsRuSender($config->require('SMSRU_API_ID'), $config->get('SMSRU_FROM'));
        }
        if ($config->isProduction()) {
            throw new \RuntimeException('В production нужен реальный SMS-провайдер (SMS_PROVIDER=smsru)');
        }
        return new LogSmsSender($root . '/var/log/sms.log');
    }

    private function orderNotifier(Config $config): OrderNotifier
    {
        $recipients = $config->list('ORDER_NOTIFY_EMAILS');
        if ($recipients === [] && $config->isProduction()) {
            throw new \RuntimeException('В production нужен ORDER_NOTIFY_EMAILS — иначе менеджеры не узнают о заявках');
        }
        return $recipients === []
            ? new LogOrderNotifier($this->logger)
            : new MailOrderNotifier($recipients, $config->get('ORDER_NOTIFY_FROM', 'app@art-active24.ru') ?? '', $this->logger);
    }
}
