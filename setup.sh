#!/usr/bin/env bash
# setup.sh

composer create-project laravel/laravel nz-term-deposit-app
cp .env.example .env
php artisan key:generate

# Git init
git init
git add .
git commit -m "Initial Laravel 10 scaffold"
