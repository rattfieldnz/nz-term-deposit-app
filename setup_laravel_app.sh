#!/bin/bash
set -e

APP_NAME="nz-term-deposits"

echo "Creating Laravel project..."
laravel new $APP_NAME --jet

cd $APP_NAME

echo "Installing npm dependencies (Jetstream uses Tailwind etc)..."
npm install && npm run dev

echo "Installing composer dependencies..."
composer require maatwebsite/excel barryvdh/laravel-dompdf nuwave/lighthouse pusher/pusher-php-server beyondcode/laravel-websockets livewire/livewire

echo "Publishing Jetstream, Livewire, Lighthouse and websocket vendor files..."

php artisan vendor:publish --tag=jetstream-config
php artisan vendor:publish --provider="Livewire\LivewireServiceProvider" --tag=config
php artisan vendor:publish --provider="Nuwave\Lighthouse\LighthouseServiceProvider" --tag=config
php artisan vendor:publish --provider="BeyondCode\LaravelWebSockets\WebSocketsServiceProvider" --tag=config

echo "Generating models and migrations..."

php artisan make:model Bank -m
php artisan make:model TermDepositRate -m
php artisan make:migration add_is_admin_to_users_table --table=users

echo "Generating controllers..."

php artisan make:controller Admin/BankController --resource --model=Bank
php artisan make:controller Admin/TermDepositRateController --resource --model=TermDepositRate
php artisan make:controller InvestmentController
php artisan make:controller ExportController
php artisan make:controller Api/BankApiController
php artisan make:controller Api/TermDepositRateApiController

echo "Generating middleware for Admin..."

php artisan make:middleware AdminMiddleware

echo "Setup completed. Please manually update migrations, models, controllers, routes, GraphQL schema, and blade views as per your app design."

echo "Run migrations:"
echo "php artisan migrate"

echo "Run development server:"
echo "php artisan serve"