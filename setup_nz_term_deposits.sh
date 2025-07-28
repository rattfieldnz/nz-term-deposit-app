#!/bin/bash
set -e

APP_NAME="nz-term-deposits"

rm -rf $APP_NAME

echo "[1/10] Creating Laravel project with Jetstream (Livewire)..."
laravel new $APP_NAME 
cd $APP_NAME

composer require laravel/jetstream
php artisan jetstream:install livewire

echo "[2/10] Installing npm dependencies and build frontend assets..."
npm install
npm run dev

echo "[3/10] Installing required composer packages..."
composer require maatwebsite/excel barryvdh/laravel-dompdf nuwave/lighthouse pusher/pusher-php-server beyondcode/laravel-websockets livewire/livewire

echo "[4/10] Publishing vendor configs..."
php artisan vendor:publish --tag=jetstream-config
php artisan vendor:publish --provider="Livewire\LivewireServiceProvider" --tag=config
php artisan vendor:publish --provider="Nuwave\Lighthouse\LighthouseServiceProvider" --tag=config
php artisan vendor:publish --provider="BeyondCode\LaravelWebSockets\WebSocketsServiceProvider" --tag=config

echo "[5/10] Creating migrations and models..."
php artisan make:model Bank -m
php artisan make:model TermDepositRate -m
php artisan make:migration add_is_admin_to_users_table --table=users

echo "[6/10] Creating controllers..."
php artisan make:controller Admin/BankController --resource --model=Bank
php artisan make:controller Admin/TermDepositRateController --resource --model=TermDepositRate
php artisan make:controller InvestmentController
php artisan make:controller ExportController
php artisan make:controller Api/BankApiController
php artisan make:controller Api/TermDepositRateApiController

echo "[7/10] Creating middleware for admin role..."
php artisan make:middleware AdminMiddleware

echo "[8/10] Creating Event for broadcasting..."
php artisan make:event TermDepositRateChanged

echo "[9/10] Creating service class for calculation..."
mkdir -p app/Services
cat > app/Services/TermDepositCalculator.php << 'EOF'
<?php
namespace App\Services;

class TermDepositCalculator
{
    public function calculate(float $principal, float $annualRate, int $termMonths): float
    {
        $years = $termMonths / 12;
        return round($principal * pow((1 + $annualRate), $years), 2);
    }

    public function growthOverTime(float $principal, float $annualRate, int $termMonths): array
    {
        $data = [];
        for ($month = 1; $month <= $termMonths; $month++) {
            $years = $month / 12;
            $data[$month] = round($principal * pow((1 + $annualRate), $years), 2);
        }
        return $data;
    }
}
EOF

echo "[10/10] Adding files for GraphQL schema, exports, views, middleware, seeder, tests..."
# [Add the rest of files via cat > as in original script]

# Insert routes only if not already present to avoid duplication
if ! grep -q "InvestmentController" routes/web.php; then
  cat >> routes/web.php <<'EOF'

// Investment routes
use App\Http\Controllers\InvestmentController;
use App\Http\Controllers\ExportController;

Route::get('/', [InvestmentController::class, 'index'])->name('home');
Route::post('/calculate', [InvestmentController::class, 'calculate'])->name('calculate');

Route::get('/export/excel', [ExportController::class, 'exportExcel'])->name('export.excel');
Route::post('/export/pdf', [ExportController::class, 'exportPdf'])->name('export.pdf');

// Admin routes with middleware
Route::middleware(['auth', 'admin'])->prefix('admin')->name('admin.')->group(function () {
    Route::resource('banks', \App\Http\Controllers\Admin\BankController::class);
    Route::resource('term-deposit-rates', \App\Http\Controllers\Admin\TermDepositRateController::class);
});
EOF
fi

if ! grep -q "BankApiController" routes/api.php; then
  cat >> routes/api.php <<'EOF'

use App\Http\Controllers\Api\BankApiController;
use App\Http\Controllers\Api\TermDepositRateApiController;

Route::middleware('auth:sanctum')->group(function() {
    Route::get('/banks', [BankApiController::class, 'index']);
    Route::get('/term-deposit-rates', [TermDepositRateApiController::class, 'index']);
});
EOF
fi

# Append AppServiceProvider register method singleton binding carefully:
APP_SERVICE_PROVIDER="app/Providers/AppServiceProvider.php"
if ! grep -q "TermDepositCalculator" $APP_SERVICE_PROVIDER; then
  sed -i '/public function register()/a\
\
        $this->app->singleton(\App\Services\TermDepositCalculator::class, function ($app) {\
            return new \App\Services\TermDepositCalculator();\
        });\
' $APP_SERVICE_PROVIDER
fi


# Migration: add_is_admin_to_users_table
php artisan make:migration add_is_admin_to_users_table --table=users
MIGRATION_IS_ADMIN=$(ls database/migrations/*add_is_admin_to_users_table.php | head -1)
cat > "$MIGRATION_IS_ADMIN" << 'EOF'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class AddIsAdminToUsersTable extends Migration
{
    public function up()
    {
        Schema::table('users', function (Blueprint $table) {
            $table->boolean('is_admin')->default(false);
        });
    }

    public function down()
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('is_admin');
        });
    }
}
EOF

php artisan make:migration create_banks_table
MIGRATION_BANKS=$(ls database/migrations/*create_banks_table.php | head -1)
cat > "$MIGRATION_BANKS" << 'EOF'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateBanksTable extends Migration
{
    public function up()
    {
        Schema::create('banks', function (Blueprint $table) {
            $table->id();
            $table->string('name')->unique();
            $table->string('website')->nullable();
            $table->string('logo_url')->nullable();
            $table->timestamps();
        });
    }

    public function down()
    {
        Schema::dropIfExists('banks');
    }
}
EOF

php artisan make:migration create_term_deposit_rates_table
MIGRATION_TDR=$(ls database/migrations/*create_term_deposit_rates_table.php | head -1)
cat > "$MIGRATION_TDR" << 'EOF'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class CreateTermDepositRatesTable extends Migration
{
    public function up()
    {
        Schema::create('term_deposit_rates', function (Blueprint $table) {
            $table->id();
            $table->foreignId('bank_id')->constrained()->cascadeOnDelete();
            $table->unsignedInteger('term_months');
            $table->decimal('interest_rate', 5, 4);
            $table->timestamps();
            $table->unique(['bank_id', 'term_months']);
        });
    }

    public function down()
    {
        Schema::dropIfExists('term_deposit_rates');
    }
}
EOF
# Models: Bank.php
cat > app/Models/Bank.php << 'EOF'
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Bank extends Model
{
    use HasFactory;

    protected $fillable = ['name', 'website', 'logo_url'];

    public function termDepositRates()
    {
        return $this->hasMany(TermDepositRate::class);
    }
}
EOF

# Models: TermDepositRate.php
cat > app/Models/TermDepositRate.php << 'EOF'
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use App\Events\TermDepositRateChanged;

class TermDepositRate extends Model
{
    use HasFactory;

    protected $fillable = ['bank_id', 'term_months', 'interest_rate'];

    protected static function booted()
    {
        static::created(function ($rate) {
            event(new TermDepositRateChanged($rate));
        });

        static::updated(function ($rate) {
            event(new TermDepositRateChanged($rate));
        });
    }

    public function bank()
    {
        return $this->belongsTo(Bank::class);
    }
}
EOF

# Event: TermDepositRateChanged.php
cat > app/Events/TermDepositRateChanged.php << 'EOF'
<?php

namespace App\Events;

use App\Models\TermDepositRate;
use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Queue\SerializesModels;

class TermDepositRateChanged implements ShouldBroadcast
{
    use InteractsWithSockets, SerializesModels;

    public $termDepositRate;

    public function __construct(TermDepositRate $termDepositRate)
    {
        $this->termDepositRate = $termDepositRate;
    }

    public function broadcastOn()
    {
        return new Channel('term-deposit-rates');
    }

    public function broadcastWith()
    {
        return [
            'id' => $this->termDepositRate->id,
            'bank_id' => $this->termDepositRate->bank_id,
            'term_months' => $this->termDepositRate->term_months,
            'interest_rate' => $this->termDepositRate->interest_rate,
            'updated_at' => $this->termDepositRate->updated_at->toIso8601String(),
        ];
    }
}
EOF

# InvestmentController.php
cat > app/Http/Controllers/InvestmentController.php << 'EOF'
<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\Bank;
use App\Services\TermDepositCalculator;

class InvestmentController extends Controller
{
    protected $calculator;

    public function __construct(TermDepositCalculator $calculator)
    {
        $this->calculator = $calculator;
    }

    public function index()
    {
        $banks = Bank::with('termDepositRates')->get();
        return view('investment.index', compact('banks'));
    }

    public function calculate(Request $request)
    {
        $request->validate([
            'amount' => 'required|numeric|min:1',
            'term_months' => 'required|integer|min:1',
        ]);

        $amount = $request->input('amount');
        $termMonths = $request->input('term_months');
        $banks = Bank::with('termDepositRates')->get();
        $results = [];

        foreach ($banks as $bank) {
            foreach ($bank->termDepositRates as $rate) {
                $effectiveTerm = min($termMonths, $rate->term_months);
                $finalAmount = $this->calculator->calculate($amount, $rate->interest_rate, $effectiveTerm);
                $growthOverTime = $this->calculator->growthOverTime($amount, $rate->interest_rate, $effectiveTerm);

                $results[] = [
                    'bank_name' => $bank->name,
                    'term_months' => $rate->term_months,
                    'interest_rate' => $rate->interest_rate,
                    'final_amount' => $finalAmount,
                    'growth_over_time' => $growthOverTime,
                ];
            }
        }

        return view('investment.results', compact('results', 'amount', 'termMonths'));
    }
}
EOF

# ExportController.php (prepare directory)
mkdir -p app/Exports
cat > app/Exports/InvestmentExport.php << 'EOF'
<?php

namespace App\Exports;

use App\Models\Bank;
use App\Services\TermDepositCalculator;
use Maatwebsite\Excel\Concerns\FromArray;
use Maatwebsite\Excel\Concerns\WithHeadings;

class InvestmentExport implements FromArray, WithHeadings
{
    protected $amount;
    protected $termMonths;
    protected $calculator;

    public function __construct($amount, $termMonths)
    {
        $this->amount = $amount;
        $this->termMonths = $termMonths;
        $this->calculator = new TermDepositCalculator();
    }

    public function array(): array
    {
        $banks = Bank::with('termDepositRates')->get();
        $rows = [];

        foreach ($banks as $bank) {
            foreach ($bank->termDepositRates as $rate) {
                $effectiveTerm = min($this->termMonths, $rate->term_months);
                $finalAmount = $this->calculator->calculate($this->amount, $rate->interest_rate, $effectiveTerm);

                $rows[] = [
                    $bank->name,
                    $rate->term_months,
                    number_format($rate->interest_rate * 100, 2),
                    $finalAmount,
                ];
            }
        }

        return $rows;
    }

    public function headings(): array
    {
        return [
            'Bank',
            'Term (Months)',
            'Interest Rate (%)',
            'Final Amount (NZD)',
        ];
    }
}
EOF

cat > app/Http/Controllers/ExportController.php << 'EOF'
<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Services\TermDepositCalculator;
use App\Models\Bank;
use Maatwebsite\Excel\Facades\Excel;
use App\Exports\InvestmentExport;
use PDF;

class ExportController extends Controller
{
    protected $calculator;

    public function __construct(TermDepositCalculator $calculator)
    {
        $this->calculator = $calculator;
    }

    public function exportExcel(Request $request)
    {
        $request->validate([
            'amount' => 'required|numeric|min:1',
            'term_months' => 'required|integer|min:1',
        ]);

        $amount = $request->input('amount');
        $termMonths = $request->input('term_months');

        return Excel::download(new InvestmentExport($amount, $termMonths), 'investment_comparison.xlsx');
    }

    public function exportPdf(Request $request)
    {
        $request->validate([
            'amount' => 'required|numeric|min:1',
            'term_months' => 'required|integer|min:1',
            'chart_image' => 'required|string',
        ]);

        $amount = $request->input('amount');
        $termMonths = $request->input('term_months');
        $chartImage = $request->input('chart_image');

        $banks = Bank::with('termDepositRates')->get();
        $results = [];

        foreach ($banks as $bank) {
            foreach ($bank->termDepositRates as $rate) {
                $effectiveTerm = min($termMonths, $rate->term_months);
                $finalAmount = $this->calculator->calculate($amount, $rate->interest_rate, $effectiveTerm);
                $growthOverTime = $this->calculator->growthOverTime($amount, $rate->interest_rate, $effectiveTerm);

                $results[] = [
                    'bank_name' => $bank->name,
                    'term_months' => $rate->term_months,
                    'interest_rate' => $rate->interest_rate,
                    'final_amount' => $finalAmount,
                    'growth_over_time' => $growthOverTime,
                ];
            }
        }
        $pdf = PDF::loadView('export.investment_pdf', compact('results', 'amount', 'termMonths', 'chartImage'));

        return $pdf->download('investment_comparison.pdf');
    }
}
EOF

# investment index blade view
mkdir -p resources/views/investment
cat > resources/views/investment/index.blade.php << 'EOF'
@extends('layouts.app')

@section('content')
<div class="max-w-4xl mx-auto p-6 bg-white rounded shadow">
    <h1 class="text-2xl font-bold mb-4">Compare Term Deposit Rates</h1>

    <form method="POST" action="{{ route('calculate') }}" x-data="{termMonths: 12}">
        @csrf

        <div class="mb-4">
            <label for="amount" class="block font-semibold mb-1">Investment Amount (NZD):</label>
            <input type="number" name="amount" id="amount" min="1" value="{{ old('amount', 10000) }}" required class="w-full border rounded p-2">
            @error('amount') <p class="text-red-600">{{ $message }}</p> @enderror
        </div>

        <div class="mb-4">
            <label for="term_months" class="block font-semibold mb-1">Investment Term (months):</label>
            <select name="term_months" id="term_months" x-model="termMonths" class="w-full border rounded p-2">
                <option value="3">3 Months</option>
                <option value="6">6 Months</option>
                <option value="12">12 Months</option>
                <option value="24">24 Months</option>
                <option value="36">36 Months</option>
            </select>
            @error('term_months') <p class="text-red-600">{{ $message }}</p> @enderror
        </div>

        <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700">Compare</button>
    </form>
</div>
@endsection
EOF

# investment results blade view
cat > resources/views/investment/results.blade.php << 'EOF'
@extends('layouts.app')

@section('content')
<div class="max-w-6xl mx-auto p-6 bg-white rounded shadow">
    <h1 class="text-2xl font-bold mb-4">Investment Return Results</h1>

    <p>Investment Amount: ${{ number_format($amount, 2) }}</p>
    <p>Investment Term: {{ $termMonths }} months</p>

    @if(count($results) === 0)
        <p>No offers available at this time.</p>
    @else
        <table class="w-full border-collapse border mb-6">
            <thead>
                <tr class="bg-gray-100">
                    <th class="border p-2">Bank</th>
                    <th class="border p-2">Term (months)</th>
                    <th class="border p-2">Interest Rate (%)</th>
                    <th class="border p-2">Final Amount ($)</th>
                </tr>
            </thead>
            <tbody>
                @foreach($results as $result)
                <tr>
                    <td class="border p-2">{{ $result['bank_name'] }}</td>
                    <td class="border p-2">{{ $result['term_months'] }}</td>
                    <td class="border p-2">{{ number_format($result['interest_rate'] * 100, 2) }}</td>
                    <td class="border p-2">{{ number_format($result['final_amount'], 2) }}</td>
                </tr>
                @endforeach
            </tbody>
        </table>

        <div>
            <a href="{{ route('export.excel', ['amount' => $amount, 'term_months' => $termMonths]) }}" class="mr-4 bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700">Export Excel</a>
            <button id="exportPdfBtn" class="bg-red-600 text-white px-4 py-2 rounded hover:bg-red-700">Export PDF</button>
        </div>

        <canvas id="investmentChart" style="max-width: 100%; height: 400px;"></canvas>
    @endif
</div>

@push('scripts')
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
document.addEventListener('DOMContentLoaded', function () {
    @php
        $datasets = [];
        foreach ($results as $result) {
            $labels = array_keys($result['growth_over_time']);
            $data = array_values($result['growth_over_time']);
            $datasets[] = [
                'label' => $result['bank_name'] . ' - ' . $result['term_months'] . ' mo @ ' . number_format($result['interest_rate']*100,2) . '%',
                'data' => $data,
                'fill' => false,
                'borderColor' => '#' . substr(md5($result['bank_name']), 0, 6),
            ];
        }
        $labels = !empty($results) ? array_keys($results[0]['growth_over_time']) : [];
    @endphp

    const ctx = document.getElementById('investmentChart').getContext('2d');
    const investmentChart = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: {!! json_encode($labels) !!},
            datasets: {!! json_encode($datasets) !!}
        },
        options: {
            responsive: true,
            plugins: {
                title: { display: true, text: 'Investment Growth Over Time (Months)' }
            },
            scales: {
                x: { title: { display: true, text: 'Months' } },
                y: { title: { display: true, text: 'Amount ($)' }, beginAtZero: true }
            }
        }
    });

    const exportPdfBtn = document.getElementById('exportPdfBtn');
    exportPdfBtn.addEventListener('click', () => {
        const chartImage = investmentChart.toBase64Image();

        const form = document.createElement('form');
        form.method = 'POST';
        form.action = "{{ route('export.pdf') }}";

        const csrfInput = document.createElement('input');
        csrfInput.name = "_token";
        csrfInput.value = "{{ csrf_token() }}";
        csrfInput.type = 'hidden';

        const amountInput = document.createElement('input');
        amountInput.name = "amount";
        amountInput.value = "{{ $amount }}";
        amountInput.type = 'hidden';

        const termInput = document.createElement('input');
        termInput.name = "term_months";
        termInput.value = "{{ $termMonths }}";
        termInput.type = 'hidden';

        const chartInput = document.createElement('input');
        chartInput.name = "chart_image";
        chartInput.value = chartImage;
        chartInput.type = 'hidden';

        form.appendChild(csrfInput);
        form.appendChild(amountInput);
        form.appendChild(termInput);
        form.appendChild(chartInput);

        document.body.appendChild(form);
        form.submit();
    });
});
</script>
@endpush
@endsection
EOF

# PDF Export view
mkdir -p resources/views/export
cat > resources/views/export/investment_pdf.blade.php << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Investment Comparison PDF</title>
    <style>
        body { font-family: sans-serif; font-size: 14px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px;}
        th, td { border: 1px solid #ddd; padding: 8px;}
        th { background-color: #f4f4f4;}
        h1, h2 { text-align: center;}
        .chart-img { display: block; margin: 0 auto 20px auto; max-width: 100%; }
    </style>
</head>
<body>
    <h1>Investment Return Comparison</h1>
    <h2>Amount: ${{ number_format($amount, 2) }} - Term: {{ $termMonths }} months</h2>

    <img class="chart-img" src="{{ $chartImage }}" alt="Investment Growth Chart"/>

    <table>
        <thead>
            <tr>
                <th>Bank</th>
                <th>Term (Months)</th>
                <th>Interest Rate (%)</th>
                <th>Final Amount (NZD)</th>
            </tr>
        </thead>
        <tbody>
            @foreach ($results as $result)
            <tr>
                <td>{{ $result['bank_name'] }}</td>
                <td>{{ $result['term_months'] }}</td>
                <td>{{ number_format($result['interest_rate'] * 100, 2) }}</td>
                <td>{{ number_format($result['final_amount'], 2) }}</td>
            </tr>
            @endforeach
        </tbody>
    </table>
</body>
</html>
EOF

# GraphQL schema
mkdir -p graphql
cat > graphql/schema.graphql << 'EOF'
type Bank {
    id: ID!
    name: String!
    website: String
    logo_url: String
    termDepositRates: [TermDepositRate!]! @hasMany
}

type TermDepositRate {
    id: ID!
    bank: Bank! @belongsTo
    termMonths: Int!
    interestRate: Float!
}

type InvestmentCalculation {
    bankName: String!
    termMonths: Int!
    interestRate: Float!
    finalAmount: Float!
    growthOverTime: [GrowthPoint!]!
}

type GrowthPoint {
    month: Int!
    amount: Float!
}

type Query {
    banks: [Bank!]! @all
    termDepositRates(bankId: ID): [TermDepositRate!]! @all
    calculateInvestment(amount: Float!, termMonths: Int!): [InvestmentCalculation!]! @field(resolver: "App\\GraphQL\\Resolvers\\InvestmentResolver@calculate")
}
EOF

# GraphQL Resolver
mkdir -p app/GraphQL/Resolvers
cat > app/GraphQL/Resolvers/InvestmentResolver.php << 'EOF'
<?php

namespace App\GraphQL\Resolvers;

use App\Models\Bank;
use App\Services\TermDepositCalculator;

class InvestmentResolver
{
    public function calculate($root, array $args)
    {
        $amount = $args['amount'];
        $termMonths = $args['termMonths'];

        $calculator = new TermDepositCalculator();
        $banks = Bank::with('termDepositRates')->get();

        $results = [];

        foreach ($banks as $bank) {
            foreach ($bank->termDepositRates as $rate) {
                $effectiveTerm = min($termMonths, $rate->term_months);
                $finalAmount = $calculator->calculate($amount, $rate->interest_rate, $effectiveTerm);
                $growthArr = $calculator->growthOverTime($amount, $rate->interest_rate, $effectiveTerm);

                $growthPoints = [];
                foreach ($growthArr as $month => $amount) {
                    $growthPoints[] = [
                        'month' => $month,
                        'amount' => $amount,
                    ];
                }

                $results[] = [
                    'bankName' => $bank->name,
                    'termMonths' => $rate->term_months,
                    'interestRate' => $rate->interest_rate,
                    'finalAmount' => $finalAmount,
                    'growthOverTime' => $growthPoints,
                ];
            }
        }

        return $results;
    }
}
EOF

# Seeders: BankSeeder.php
mkdir -p database/seeders
cat > database/seeders/BankSeeder.php << 'EOF'
<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Bank;
use App\Models\TermDepositRate;

class BankSeeder extends Seeder
{
    public function run()
    {
        $banks = [
            [
                'name' => 'ANZ',
                'website' => 'https://www.anz.co.nz',
                'logo_url' => 'https://www.anz.co.nz/etc/designs/anz-nz/clientlibs/images/svg/ANZ_logo.svg',
                'rates' => [
                    ['term_months' => 3, 'interest_rate' => 0.035],
                    ['term_months' => 6, 'interest_rate' => 0.037],
                    ['term_months' => 12, 'interest_rate' => 0.04],
                ]
            ],
            [
                'name' => 'Westpac',
                'website' => 'https://www.westpac.co.nz',
                'logo_url' => 'https://www.westpac.co.nz/assets/westpac/icons/westpac-icon.svg',
                'rates' => [
                    ['term_months' => 6, 'interest_rate' => 0.036],
                    ['term_months' => 12, 'interest_rate' => 0.039],
                    ['term_months' => 24, 'interest_rate' => 0.042],
                ]
            ],
            [
                'name' => 'BNZ',
                'website' => 'https://www.bnz.co.nz',
                'logo_url' => 'https://www.bnz.co.nz/assets/logos/bnz-logo.svg',
                'rates' => [
                    ['term_months' => 3, 'interest_rate' => 0.034],
                    ['term_months' => 12, 'interest_rate' => 0.038],
                    ['term_months' => 36, 'interest_rate' => 0.045],
                ]
            ],
        ];

        foreach ($banks as $bankData) {
            $bank = Bank::create([
                'name' => $bankData['name'],
                'website' => $bankData['website'],
                'logo_url' => $bankData['logo_url'],
            ]);

            foreach ($bankData['rates'] as $rate) {
                TermDepositRate::create([
                    'bank_id' => $bank->id,
                    'term_months' => $rate['term_months'],
                    'interest_rate' => $rate['interest_rate'],
                ]);
            }
        }
    }
}
EOF

# DatabaseSeeder.php update
cat > database/seeders/DatabaseSeeder.php << 'EOF'
<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run()
    {
        $this->call(BankSeeder::class);
    }
}
EOF

echo "Running migrations and seeders..."
php artisan migrate --seed

# PHPUnit tests for TermDepositCalculator
mkdir -p tests/Unit
cat > tests/Unit/TermDepositCalculatorTest.php << 'EOF'
<?php

namespace Tests\Unit;

use PHPUnit\Framework\TestCase;
use App\Services\TermDepositCalculator;

class TermDepositCalculatorTest extends TestCase
{
    protected TermDepositCalculator $calculator;

    protected function setUp(): void
    {
        parent::setUp();
        $this->calculator = new TermDepositCalculator();
    }

    public function test_calculate_compound_interest()
    {
        $principal = 10000;
        $annualRate = 0.05; // 5%
        $termMonths = 12;

        $finalAmount = $this->calculator->calculate($principal, $annualRate, $termMonths);

        $this->assertEquals(10500, $finalAmount);
    }

    public function test_growth_over_time()
    {
        $principal = 10000;
        $annualRate = 0.05;
        $termMonths = 6;

        $growth = $this->calculator->growthOverTime($principal, $annualRate, $termMonths);
        $this->assertCount($termMonths, $growth);
        $this->assertGreaterThan($principal, $growth[1]);
    }
}
EOF

# Feature API test for BankApi
mkdir -p tests/Feature
cat > tests/Feature/BankApiTest.php << 'EOF'
<?php

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\User;
use App\Models\Bank;
use Laravel\Sanctum\Sanctum;

class BankApiTest extends TestCase
{
    public function test_authenticated_user_can_get_banks()
    {
        $user = User::factory()->create();
        Bank::factory()->count(3)->create();

        Sanctum::actingAs($user);

        $response = $this->getJson('/api/banks');

        $response->assertStatus(200)
                 ->assertJsonCount(3);
    }

    public function test_guest_cannot_access_banks_api()
    {
        $response = $this->getJson('/api/banks');
        $response->assertStatus(401);
    }
}
EOF

# Add routes to web.php and api.php
echo "[1/6] Adding web routes to routes/web.php..."
cat >> routes/web.php << 'EOF'

// Investment routes
use App\Http\Controllers\InvestmentController;
use App\Http\Controllers\ExportController;

Route::get('/', [InvestmentController::class, 'index'])->name('home');
Route::post('/calculate', [InvestmentController::class, 'calculate'])->name('calculate');

Route::get('/export/excel', [ExportController::class, 'exportExcel'])->name('export.excel');
Route::post('/export/pdf', [ExportController::class, 'exportPdf'])->name('export.pdf');

// Admin routes with middleware
Route::middleware(['auth', 'admin'])->prefix('admin')->name('admin.')->group(function () {
    Route::resource('banks', \App\Http\Controllers\Admin\BankController::class);
    Route::resource('term-deposit-rates', \App\Http\Controllers\Admin\TermDepositRateController::class);
});
EOF

echo "[2/6] Adding api routes to routes/api.php..."
cat >> routes/api.php << 'EOF'

use App\Http\Controllers\Api\BankApiController;
use App\Http\Controllers\Api\TermDepositRateApiController;

Route::middleware('auth:sanctum')->group(function() {
    Route::get('/banks', [BankApiController::class, 'index']);
    Route::get('/term-deposit-rates', [TermDepositRateApiController::class, 'index']);
});
EOF

echo "[3/6] Binding TermDepositCalculator singleton in AppServiceProvider..."
APP_SERVICE_PROVIDER="app/Providers/AppServiceProvider.php"
if ! grep -q "use App\Services\TermDepositCalculator;" $APP_SERVICE_PROVIDER; then
    sed -i "/namespace App\\\Providers;/a use App\Services\TermDepositCalculator;" $APP_SERVICE_PROVIDER
fi

awk '
/public function register\(\)/,/\}/ {
    if (!found && /public function register\(\)/) {
        print;
        print "    {";
        print "        $this->app->singleton(TermDepositCalculator::class, function ($app) {";
        print "            return new TermDepositCalculator();";
        print "        });";
        found = 1;
        next
    }
    if (found && /\}/) {
        print;
        found = 2;
        next
    }
    if (found==1) next
}
{ if(!found || found==2) print }
' $APP_SERVICE_PROVIDER > tmp_AppServiceProvider.php

mv tmp_AppServiceProvider.php $APP_SERVICE_PROVIDER

echo "[4/6] Running migrations and seeding database..."
php artisan migrate --seed

echo "[5/6] Reminder: Configure your .env file with database and broadcasting info."
echo "Set BROADCAST_DRIVER=pusher or laravel-websockets with proper keys."

echo "[6/6] Running PHPUnit tests to verify setup..."
php artisan test

echo "Setup complete! Run your server with 'php artisan serve' and rebuild assets with 'npm run dev'."

# Instructions to wire frontend JS for Echo & Pusher:
echo "To enable real-time broadcasting:"
echo "- Install JS deps: npm install --save laravel-echo pusher-js"
echo "- Configure resources/js/bootstrap.js with Echo Pusher setup"
echo "- Add Pusher credentials in .env: PUSHER_APP_ID, PUSHER_APP_KEY, PUSHER_APP_SECRET, PUSHER_APP_CLUSTER"
echo "- Run 'npm run dev'"
echo "- Listen to broadcast channels in your JS or Blade files (example included in previous instructions)."

# Instructions to add Livewire InvestmentComparison component:
echo "To add Livewire InvestmentComparison component:"
echo "- Run 'php artisan make:livewire InvestmentComparison'"
echo "- Implement component logic and blade as provided previously."
echo "- Include @livewire('investment-comparison') in your desired blade."
echo "- Ensure @livewireStyles and @livewireScripts are present in your main layout."