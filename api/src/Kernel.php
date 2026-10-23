<?php

declare(strict_types=1);

namespace App;

use App\Http\Controller\AuthController;
use App\Http\Controller\CartController;
use App\Http\Controller\CatalogController;
use App\Http\Controller\ContentController;
use App\Http\Controller\DriverController;
use App\Http\Controller\ManagerCabinetController;
use App\Http\Controller\MeController;
use App\Http\Controller\OrderCabinetController;
use App\Http\Controller\OrderController;
use App\Http\Controller\VenueController;
use App\Http\HttpError;
use App\Http\Middleware\Authenticate;
use App\Http\Middleware\OptionalAuthenticate;
use App\Http\Middleware\Throttle;
use App\Http\Request;
use App\Http\Response;
use App\Http\Router;

/**
 * Маршруты API v1 и единая обработка ошибок.
 */
final class Kernel
{
    private readonly Router $router;

    public function __construct(private readonly Container $c)
    {
        $this->router = $this->routes();
    }

    public function handle(Request $request): Response
    {
        $basePath = rtrim($this->c->config->get('API_BASE_PATH', '') ?? '', '/');
        if ($basePath !== '' && ($request->path === $basePath || str_starts_with($request->path, $basePath . '/'))) {
            $request = new Request(
                $request->method,
                substr($request->path, strlen($basePath)) ?: '/',
                $request->query,
                $request->headers,
                $request->rawBody,
                $request->clientIp,
            );
        }
        try {
            return $this->router->dispatch($request);
        } catch (HttpError $e) {
            $response = Response::error($e);
            return $e->retryAfter !== null ? $response->withHeader('Retry-After', (string) $e->retryAfter) : $response;
        } catch (\Throwable $e) {
            $this->c->logger->error($e->getMessage(), [
                'exception' => $e::class,
                'at' => $e->getFile() . ':' . $e->getLine(),
                'path' => $request->path,
            ]);
            return Response::error(new HttpError(500, 'server_error', 'Что-то пошло не так. Попробуйте ещё раз'));
        }
    }

    private function routes(): Router
    {
        $c = $this->c;
        $r = new Router();
        $auth = [new Authenticate($c->sessions, $c->users, $c->managers)];
        $manager = [new Authenticate($c->sessions, $c->users, $c->managers, 'manager')];
        $heavy = static fn (string $name): array => [new Throttle($c->limiter, $name, 120)];

        $catalog = new CatalogController($c->catalog, $c->venues, $c->content);
        $r->add('GET', '/v1/home', $catalog->home(...));
        $r->add('GET', '/v1/info', $catalog->info(...));
        $r->add('GET', '/v1/catalog/tree', $catalog->tree(...));
        $r->add('GET', '/v1/categories/{id}', $catalog->category(...));
        $r->add('GET', '/v1/categories/{id}/products', $catalog->categoryProducts(...));
        $r->add('GET', '/v1/products/{id}', $catalog->product(...));
        $r->add('GET', '/v1/resolve', $catalog->resolve(...));
        $r->add('GET', '/v1/search', $catalog->search(...), $heavy('search'));

        $content = new ContentController($c->content);
        $r->add('GET', '/v1/sale', $content->sale(...));
        $r->add('GET', '/v1/cases', $content->cases(...));
        $r->add('GET', '/v1/cases/{slug}', $content->caseStudy(...));

        $venues = new VenueController($c->venues);
        $r->add('GET', '/v1/venues', $venues->list(...));
        $r->add('GET', '/v1/venues/filters', $venues->filters(...));
        $r->add('GET', '/v1/venues/{id}', $venues->show(...));

        $optionalAuth = new OptionalAuthenticate($c->sessions, $c->users, $c->managers);
        $cart = new CartController($c->quotes, $c->carts, $c->loyalty);
        $r->add('POST', '/v1/cart/quote', $cart->quote(...), [...$heavy('quote'), $optionalAuth]);
        $r->add('GET', '/v1/cart', $cart->get(...), $auth);
        $r->add('PUT', '/v1/cart', $cart->put(...), $auth);

        $authController = new AuthController($c->otp, $c->sessions, $c->users, $c->managers);
        $r->add('POST', '/v1/auth/code', $authController->requestCode(...));
        $r->add('POST', '/v1/auth/verify', $authController->verify(...));
        $r->add('POST', '/v1/auth/refresh', $authController->refresh(...));
        $r->add('POST', '/v1/auth/logout', $authController->logout(...), $auth);

        $me = new MeController($c->users, $c->favorites, $c->devices, $c->catalog);
        $r->add('GET', '/v1/me', $me->show(...), $auth);
        $r->add('PATCH', '/v1/me', $me->update(...), $auth);
        $r->add('GET', '/v1/me/favorites', $me->favorites(...), $auth);
        $r->add('PUT', '/v1/me/favorites', $me->replaceFavorites(...), $auth);
        $r->add('POST', '/v1/me/devices', $me->registerDevice(...), $auth);
        $r->add('DELETE', '/v1/me/devices', $me->unregisterDevice(...), $auth);

        $orders = new OrderController($c->orders);
        $r->add('GET', '/v1/orders', $orders->list(...), $auth);
        $r->add('POST', '/v1/orders', $orders->create(...), $auth);
        $r->add('GET', '/v1/orders/{id}', $orders->show(...), $auth);
        $r->add('POST', '/v1/orders/{id}/cancel', $orders->cancel(...), $auth);
        $r->add('POST', '/v1/requests', $orders->createRequest(...), $auth);
        $r->add('GET', '/v1/manager/orders', $orders->managerList(...), $manager);
        $r->add('GET', '/v1/manager/orders/{id}', $orders->show(...), $manager);
        $r->add('PATCH', '/v1/manager/orders/{id}', $orders->managerUpdate(...), $manager);

        // Личный кабинет заказа
        $cabinet = new OrderCabinetController($c->orders, $c->composition, $c->vehicles, $c->reviews, $c->claims, $c->documents, $c->loyalty);
        $r->add('GET', '/v1/orders/{id}/composition', $cabinet->composition(...), $auth);
        $r->add('GET', '/v1/orders/{id}/vehicle', $cabinet->vehicle(...), $auth);
        $r->add('POST', '/v1/orders/{id}/review', $cabinet->review(...), $auth);
        $r->add('GET', '/v1/orders/{id}/claims', $cabinet->claims(...), $auth);
        $r->add('POST', '/v1/orders/{id}/claims', $cabinet->createClaim(...), $auth);
        $r->add('GET', '/v1/orders/{id}/documents', $cabinet->documents(...), $auth);
        $r->add('GET', '/v1/me/loyalty', $cabinet->loyalty(...), $auth);

        $driver = new DriverController($c->vehicles);
        $r->add('POST', '/v1/driver/orders/{id}/location', $driver->location(...), $heavy('driver'));

        $mc = new ManagerCabinetController($c->orders, $c->composition, $c->managerDocuments, $c->vehicles, $c->claims, $c->loyalty);
        $r->add('PUT', '/v1/manager/orders/{id}/composition', $mc->putComposition(...), $manager);
        $r->add('DELETE', '/v1/manager/orders/{id}/composition', $mc->deleteComposition(...), $manager);
        $r->add('POST', '/v1/manager/orders/{id}/documents', $mc->addDocument(...), $manager);
        $r->add('DELETE', '/v1/manager/orders/{id}/documents/{docId}', $mc->deleteDocument(...), $manager);
        $r->add('POST', '/v1/manager/orders/{id}/driver', $mc->assignDriver(...), $manager);
        $r->add('PUT', '/v1/manager/orders/{id}/links', $mc->links(...), $manager);
        $r->add('GET', '/v1/manager/claims', $mc->claims(...), $manager);
        $r->add('PATCH', '/v1/manager/claims/{id}', $mc->updateClaim(...), $manager);
        $r->add('GET', '/v1/manager/users/{id}/loyalty', $mc->loyalty(...), $manager);
        $r->add('PUT', '/v1/manager/users/{id}/loyalty', $mc->setLoyalty(...), $manager);

        return $r;
    }
}
