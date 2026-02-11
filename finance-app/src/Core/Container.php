<?php

declare(strict_types=1);

namespace App\Core;

use Closure;
use Exception;
use ReflectionClass;
use ReflectionParameter;

/**
 * Dependency Injection Container
 * Manages service instantiation and dependency resolution
 */
class Container
{
    private array $bindings = [];
    private array $instances = [];
    private array $singletons = [];

    /**
     * Bind a service to the container
     */
    public function bind(string $id, Closure|string $resolver): void
    {
        $this->bindings[$id] = $resolver;
    }

    /**
     * Bind a singleton service to the container
     */
    public function singleton(string $id, Closure|string $resolver): void
    {
        $this->bindings[$id] = $resolver;
        $this->singletons[$id] = true;
    }

    /**
     * Get a service from the container
     */
    public function get(string $id): mixed
    {
        // Return existing singleton instance
        if (isset($this->instances[$id])) {
            return $this->instances[$id];
        }

        // Resolve from binding
        if (isset($this->bindings[$id])) {
            $resolver = $this->bindings[$id];

            if ($resolver instanceof Closure) {
                $instance = $resolver($this);
            } else {
                $instance = $this->resolve($resolver);
            }

            // Store singleton instances
            if (isset($this->singletons[$id])) {
                $this->instances[$id] = $instance;
            }

            return $instance;
        }

        // Auto-resolve class
        return $this->resolve($id);
    }

    /**
     * Check if service is bound
     */
    public function has(string $id): bool
    {
        return isset($this->bindings[$id]) || class_exists($id);
    }

    /**
     * Resolve class with dependencies
     */
    private function resolve(string $class): object
    {
        if (!class_exists($class)) {
            throw new Exception("Class {$class} does not exist");
        }

        $reflector = new ReflectionClass($class);

        if (!$reflector->isInstantiable()) {
            throw new Exception("Class {$class} is not instantiable");
        }

        $constructor = $reflector->getConstructor();

        if ($constructor === null) {
            return new $class();
        }

        $parameters = $constructor->getParameters();
        $dependencies = $this->resolveDependencies($parameters);

        return $reflector->newInstanceArgs($dependencies);
    }

    /**
     * Resolve constructor dependencies
     */
    private function resolveDependencies(array $parameters): array
    {
        $dependencies = [];

        foreach ($parameters as $parameter) {
            $type = $parameter->getType();

            if ($type === null) {
                if ($parameter->isDefaultValueAvailable()) {
                    $dependencies[] = $parameter->getDefaultValue();
                } else {
                    throw new Exception("Cannot resolve parameter {$parameter->getName()}");
                }
            } elseif (!$type instanceof \ReflectionNamedType || $type->isBuiltin()) {
                if ($parameter->isDefaultValueAvailable()) {
                    $dependencies[] = $parameter->getDefaultValue();
                } else {
                    throw new Exception("Cannot resolve builtin parameter {$parameter->getName()}");
                }
            } else {
                $dependencies[] = $this->get($type->getName());
            }
        }

        return $dependencies;
    }

    /**
     * Call a method and inject dependencies
     */
    public function call(callable|array $callback, array $parameters = []): mixed
    {
        if (is_array($callback)) {
            [$class, $method] = $callback;

            if (is_string($class)) {
                $class = $this->get($class);
            }

            $reflector = new \ReflectionMethod($class, $method);
        } else {
            $reflector = new \ReflectionFunction($callback);
        }

        $dependencies = $this->resolveDependencies($reflector->getParameters());
        $dependencies = array_merge($dependencies, $parameters);

        return $reflector->invokeArgs(
            is_array($callback) ? $class : null,
            $dependencies
        );
    }
}
