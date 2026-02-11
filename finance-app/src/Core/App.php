<?php

declare(strict_types=1);

namespace App\Core;

use App\Core\Container;
use App\Core\Router;
use App\Core\Request;
use App\Core\Response;
use App\Core\Config;
use App\Core\Database;
use App\Core\Session;
use App\Middleware\MiddlewareStack;
use Exception;

/**
 * Main Application Class
 * Bootstraps and runs the application
 */
class App
{
    private static ?App $instance = null;
    private Container $container;
    private Router $router;
    private Config $config;

    private function __construct()
    {
        $this->container = new Container();
        $this->registerCoreBindings();
    }

    public static function getInstance(): self
    {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    /**
     * Bootstrap the application
     */
    public function bootstrap(): void
    {
        // Error handling
        $this->setupErrorHandling();

        // Load environment variables
        $this->loadEnvironment();

        // Initialize configuration
        $this->config = new Config();
        $this->container->singleton(Config::class, fn() => $this->config);

        // Initialize database
        $db = new Database($this->config);
        $this->container->singleton(Database::class, fn() => $db);

        // Initialize session
        $session = new Session($this->config);
        $session->start();
        $this->container->singleton(Session::class, fn() => $session);

        // Initialize router
        $this->router = new Router($this->container);
        $this->container->singleton(Router::class, fn() => $this->router);

        // Load routes
        $this->loadRoutes();
    }

    /**
     * Run the application
     */
    public function run(): void
    {
        try {
            $request = Request::createFromGlobals();
            $this->container->singleton(Request::class, fn() => $request);

            // Build middleware stack
            $middlewareStack = new MiddlewareStack($this->container);
            $this->loadMiddleware($middlewareStack);

            // Handle request through middleware
            $response = $middlewareStack->handle($request, function($request) {
                return $this->router->dispatch($request);
            });

            $response->send();

        } catch (Exception $e) {
            $this->handleException($e);
        }
    }

    /**
     * Get service from container
     */
    public function get(string $id): mixed
    {
        return $this->container->get($id);
    }

    /**
     * Register core service bindings
     */
    private function registerCoreBindings(): void
    {
        $this->container->singleton(Container::class, fn() => $this->container);
    }

    /**
     * Setup error and exception handling
     */
    private function setupErrorHandling(): void
    {
        error_reporting(E_ALL);
        set_error_handler([$this, 'handleError']);
        set_exception_handler([$this, 'handleException']);
        register_shutdown_function([$this, 'handleShutdown']);
    }

    /**
     * Load environment variables from .env file
     */
    private function loadEnvironment(): void
    {
        $envFile = dirname(__DIR__, 2) . '/.env';

        if (file_exists($envFile)) {
            $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($lines as $line) {
                if (strpos(trim($line), '#') === 0) {
                    continue;
                }

                if (strpos($line, '=') !== false) {
                    list($key, $value) = explode('=', $line, 2);
                    $key = trim($key);
                    $value = trim($value);

                    // Remove quotes
                    $value = trim($value, '"\'');

                    if (!array_key_exists($key, $_ENV)) {
                        $_ENV[$key] = $value;
                        putenv("$key=$value");
                    }
                }
            }
        }
    }

    /**
     * Load application routes
     */
    private function loadRoutes(): void
    {
        $routesFile = dirname(__DIR__, 2) . '/config/routes.php';
        if (file_exists($routesFile)) {
            require $routesFile;
        }
    }

    /**
     * Load middleware stack
     */
    private function loadMiddleware(MiddlewareStack $stack): void
    {
        // Global middleware
        $stack->add(\App\Middleware\SecurityHeadersMiddleware::class);
        $stack->add(\App\Middleware\CsrfMiddleware::class);
        $stack->add(\App\Middleware\RateLimitMiddleware::class);
    }

    /**
     * Handle PHP errors
     */
    public function handleError(int $errno, string $errstr, string $errfile, int $errline): bool
    {
        if (!(error_reporting() & $errno)) {
            return false;
        }

        throw new \ErrorException($errstr, 0, $errno, $errfile, $errline);
    }

    /**
     * Handle exceptions
     */
    public function handleException(\Throwable $exception): void
    {
        // Log exception
        $this->logException($exception);

        // Show error page
        $debug = ($_ENV['APP_DEBUG'] ?? 'false') === 'true';

        http_response_code(500);

        if ($debug) {
            echo "<h1>Application Error</h1>";
            echo "<p><strong>Message:</strong> " . htmlspecialchars($exception->getMessage()) . "</p>";
            echo "<p><strong>File:</strong> " . htmlspecialchars($exception->getFile()) . ":" . $exception->getLine() . "</p>";
            echo "<pre>" . htmlspecialchars($exception->getTraceAsString()) . "</pre>";
        } else {
            echo "<h1>500 Internal Server Error</h1>";
            echo "<p>An unexpected error occurred. Please try again later.</p>";
        }
    }

    /**
     * Handle shutdown
     */
    public function handleShutdown(): void
    {
        $error = error_get_last();
        if ($error !== null && in_array($error['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
            $this->handleException(
                new \ErrorException($error['message'], 0, $error['type'], $error['file'], $error['line'])
            );
        }
    }

    /**
     * Log exception
     */
    private function logException(\Throwable $exception): void
    {
        $logFile = dirname(__DIR__, 2) . '/storage/logs/app.log';
        $logDir = dirname($logFile);

        if (!is_dir($logDir)) {
            mkdir($logDir, 0755, true);
        }

        $message = sprintf(
            "[%s] %s: %s in %s:%d\n",
            date('Y-m-d H:i:s'),
            get_class($exception),
            $exception->getMessage(),
            $exception->getFile(),
            $exception->getLine()
        );

        error_log($message, 3, $logFile);
    }
}
