#!/usr/bin/env bash
# setup_db.sh
# This script creates migrations for banks, terms, rates,
# seeds initial data, and runs migrate:fresh --seed.
# It follows PSR-12, SOLID, DRY, and KISS principles.

set -euo pipefail

cd nz-term-deposit-app

echo "▶ Creating migrations…"

# 1. Generate migration stubs
php artisan make:migration create_banks_table --create=banks
php artisan make:migration create_terms_table --create=terms
php artisan make:migration create_rates_table --create=rates

# 2. Overwrite create_banks_table migration
banks_migration="$(ls database/migrations/*_create_banks_table.php | tail -n1)"
cat > "$banks_migration" << 'EOM'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('banks', function (Blueprint $table) {
            $table->id();
            $table->string('name')->unique();
            $table->string('website')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('banks');
    }
};
EOM

# 3. Overwrite create_terms_table migration
terms_migration="$(ls database/migrations/*_create_terms_table.php | tail -n1)"
cat > "$terms_migration" << 'EOM'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('terms', function (Blueprint $table) {
            $table->id();
            $table->unsignedSmallInteger('months');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('terms');
    }
};
EOM

# 4. Overwrite create_rates_table migration
rates_migration="$(ls database/migrations/*_create_rates_table.php | tail -n1)"
cat > "$rates_migration" << 'EOM'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('rates', function (Blueprint $table) {
            $table->id();
            $table->foreignId('bank_id')->constrained()->cascadeOnDelete();
            $table->foreignId('term_id')->constrained()->cascadeOnDelete();
            $table->decimal('interest_rate', 5, 2);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('rates');
    }
};
EOM

echo "✔ Migrations created and populated."

echo "▶ Creating BankTermRateSeeder…"
php artisan make:seeder BankTermRateSeeder

# 5. Overwrite BankTermRateSeeder
cat > database/seeders/BankTermRateSeeder.php << 'EOM'
<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Bank;
use App\Models\Term;
use App\Models\Rate;

class BankTermRateSeeder extends Seeder
{
    public function run(): void
    {
        $banks = ['ANZ', 'ASB', 'BNZ', 'Westpac', 'Kiwibank', 'TSB', 'SBS'];
        $terms = [3, 6, 12, 24];

        foreach ($banks as $bankName) {
            $bank = Bank::create([
                'name'    => $bankName,
                'website' => null,
            ]);

            foreach ($terms as $months) {
                $term = Term::firstOrCreate(['months' => $months]);
                Rate::create([
                    'bank_id'       => $bank->id,
                    'term_id'       => $term->id,
                    'interest_rate' => rand(300, 600) / 100, // 3.00%–6.00%
                ]);
            }
        }
    }
}
EOM

echo "✔ Seeder created."

echo "▶ Registering BankTermRateSeeder in DatabaseSeeder…"
# 6. Ensure the seeder is called in DatabaseSeeder
db_seeder="database/seeders/DatabaseSeeder.php"
if ! grep -q "BankTermRateSeeder" "$db_seeder"; then
  # Insert call() before the final closing brace of run()
  sed -i "/public function run()/,/}/ s/}/        \$this->call(BankTermRateSeeder::class);\n    }/" "$db_seeder"
fi
echo "✔ DatabaseSeeder updated."

echo "▶ Running migrations and seeders…"
php artisan migrate:fresh --seed

echo "🎉 Database schema created and seeded successfully."