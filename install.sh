#!/usr/bin/env bash
# install.sh

cd nz-term-deposit-app

composer require laravel/jetstream laravel/sanctum nuwave/lighthouse \
                 maatwebsite/excel barryvdh/laravel-dompdf \
                 filament/filament beyondcode/laravel-websockets

# Jetstream + Livewire
php artisan jetstream:install livewire --teams=false
npm install && npm run dev

# Publish vendor assets
php artisan vendor:publish --tag=fortify-config
php artisan vendor:publish --tag=filament-config
php artisan vendor:publish --provider="BeyondCode\LaravelWebSockets\WebSocketsServiceProvider" --tag="config"

php artisan migrate