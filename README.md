<!DOCTYPE html> 
<html lang="en"> 
<head> 
<meta charset="UTF-8"> 
<title>NZ Term Deposits Application</title> 
</head> 
<body>
<div>
<h1>NZ Term Deposits Application</h1>
<p>A Laravel 10 application to track term deposit rates and terms for major banks and financial institutions in New Zealand. This app allows visitors to enter an investment amount and compare returns across banks over specified term lengths. It includes both REST and GraphQL APIs, real-time updates, export options, and an admin dashboard for managing banks and rates.</p>
<hr>
<h2>Features</h2>
<ul>
	<li>Laravel 10 project with Jetstream (Livewire) for authentication and SPA frontend</li>
	<li>User model supports admin role (is_admin flag)</li>
	<li>Models for Banks and Term Deposit Rates with full relations</li>
	<li>Middleware restricting admin routes to administrators</li>
	<li>REST API endpoints secured with Laravel Sanctum</li>
	<li>GraphQL API powered by Lighthouse</li>
	<li>Real-time WebSocket updates using Laravel Websockets and Pusher protocol</li>
	<li>Investment calculation service with compound interest formula and growth over time</li>
	<li>Frontend investment calculator with Livewire SPA components</li>
	<li>Export results as Excel or PDF with embedded investment growth charts</li>
	<li>PHPUnit test coverage for models, middleware, services, and APIs</li>
	<li>Database seeders with example data for a quick start</li>
	<li>Fully Dockerized with Nginx, PHP-FPM, MySQL, Redis, WebSockets, and PhpMyAdmin support</li>
	<li>Local volume mappings for easy code editing and persistent data storage</li>
</ul>
<hr>
<h2>Requirements</h2>
<ul>
	<li>Docker 20.x or newer (for Dockerized setup)</li>
	<li>Docker Compose 1.29+ or native Docker Compose</li>
	<li>Optional Laravel Installer (composer global require laravel/installer) for local development without Docker</li>
	<li>Node.js 16+ and npm (for frontend assets)</li>
</ul>
<hr>
<h2>Installation / Setup</h2>
<ol>
	<li>
		<h2>Clone the repository</h2>
		<code>git clone https://github.com/yourusername/nz-term-deposits.git
cd nz-term-deposits
</code>
	</li>
	<li>
		<h2>Copy .env configuration</h2>
		<code>cp .env.example .env</code>
	</li>
	<li>
		<h2>Update .env with your database credentials and Pusher settings for broadcasting:</h2>
		<p><code>DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=nz_term_deposits
DB_USERNAME=nzuser
DB_PASSWORD=nzpassword
BROADCAST_DRIVER=pusher
PUSHER_APP_ID=your-app-id
PUSHER_APP_KEY=your-app-key
PUSHER_APP_SECRET=your-app-secret
PUSHER_HOST=127.0.0.1
PUSHER_PORT=6001
PUSHER_SCHEME=http
PUSHER_APP_CLUSTER=mt1
</code></p>
	</li>
	<li>
		<h2>Adjust Pusher configuration as needed.</h2>
        <ul>
			<li>
				<h2>Docker Setup (Recommended):</h2>
				<p>Start your full development environment including PhpMyAdmin:</p>
				<p><code>docker-compose up -d</code></p>
				<ul>
					<li>Laravel PHP-FPM listens on port 9000</li>
					<li>Nginx webserver listens on port 8080</li>
					<li>MySQL database listens on port 3306</li>
					<li>Redis listens on port 6379</li>
					<li>Laravel WebSockets listens on port 6001</li>
					<li>PhpMyAdmin listens on port 8081</li>
				</ul>
			</li>
		</ul>
    </li>
    <li><h2>Laravel Setup inside Docker container</h2>
		<ol>
			<li>
				<p>Open interactive shell inside the app container:</p>
				<p><code>docker exec -it nz-term-deposits-app bash</code></p>
			</li>
			<li>
				<p>Run migrations and seed the database:</p>
				<p><code>php artisan migrate --seed</code></p>
			</li>
			<li>
				<p>Compile frontend assets (inside container or locally if Node.js installed):</p>
				<p><code>npm run dev</code></p>
			</li>
			<li>
				<p>Start websockets server (run in separate container or terminal):</p>
				<p><code>php artisan websockets:serve --host=0.0.0.0 --port=6001</code></p>
			</li>
		</ol>
	</li>
	<li><h2>Access your application:</h2>
		<ol>
			<li>Open your browser at http://localhost:8080 to view the app frontend.</li>
			<li>Admin panel routes require login; use seeded admin user:
			<ul>
				<li>Email: admin@example.com</li>
				<li>Password: password</li>
			</ul>
            <li>PhpMyAdmin available at http://localhost:8081 to manage MySQL database directly.</li>
		</ol>
	</li>
</ol>

<hr>
<h2>Local Development (Without Docker)</h2>
<p>If you prefer local installation:</p>
<ul>
	<li>Install PHP 8.2, Composer, MySQL, Redis, Node.js</li>
	<li>Run migrations and seeders with php artisan migrate --seed</li>
	<li>Run development server with php artisan serve</li>
	<li>Build assets using npm install and npm run dev</li>
	<li>Start Laravel WebSockets server for real-time features.</li>
</ul>
<hr>
<h2>API Documentation</h2>
<h3>REST API Endpoints (Sanctum Authentication Required)</h3>
<ul>
	<li>GET /api/banks — Retrieve all banks with term deposit rates</li>
	<li>GET /api/term-deposit-rates — Retrieve all term deposit rates, filterable by bank_id</li>
</ul>
<h3>GraphQL Endpoint</h3>
<ul>
	<li>Default endpoint at /graphql</li>
	<li>Supported queries:
		<ul>
			<li>banks: List banks with rates</li>
			<li>termDepositRates: List term deposit rates, optionally filtered by bankId</li>
			<li>calculateInvestment(amount: Float!, termMonths: Int!): Get investment calculation results with growth data</li>
		</ul>
	</li>
</ul>
<hr>
<h2>Testing</h2>
<p>Run PHPUnit tests using:</p>
<p><code>php artisan test</code></p>
<p>Tests cover:</p>
<ul>
	<li>Models and relationships</li>
	<li>TermDepositCalculator service accuracy</li>
	<li>Middleware authorization</li>
	<li>API endpoint authorization and responses</li>
</ul>
<hr>
<h2>Exporting Data</h2>
<p>On the investment results page, you can export comparison data:</p>
<ul>
	<li>Excel .xlsx format via "Export Excel" button</li>
	<li>PDF with embedded chart via "Export PDF" button</li>
</ul>
<hr>
<h2>Directory Structure Notes</h2>
<ul>
	<li>app/Models — Eloquent models (Bank, TermDepositRate, User)</li>
	<li>app/Services — Business logic: TermDepositCalculator</li>
	<li>app/Http/Controllers — MVC controllers split for admin, API, frontend, export</li>
	<li>app/Http/Middleware — Custom Admin middleware</li>
	<li>database/factories — Model factories for seeding and testing</li>
	<li>database/seeders — Seeders to populate initial data</li>
	<li>graphql/ — GraphQL schema definition file</li>
	<li>docker/ — Nginx configuration for Docker container</li>
	<li>tests/ — PHPUnit tests for unit and feature coverage</li>
</ul>
<hr>
<h2>Broadcasting &amp; WebSockets</h2>
<p>Uses Laravel Websockets (BeyondCode) configured for real-time broadcast of changes in term deposit rates under channel term-deposit-rates. Compatible with Pusher JS client on frontend.</p>
<hr>
<h2>Customization &amp; Extensibility</h2>
<ul>
	<li>Add additional users with is_admin flag for multi-admin support.</li>
	<li>Extend models or add new ones to enhance banking data.</li>
	<li>Modify frontend blade templates or convert to Vue/React as per requirements.</li>
	<li>Add front-end tests and API docs for improved quality.</li>
</ul>
<hr>
<h2>Common Commands</h2>
<table>
<tr>
<th>Command</th><th>Description</th>
</tr>
<tr>
<td><code>php artisan migrate</code></td><td>Run migrations</td>
</tr>
<tr>
<td><code>php artisan migrate --seed</code></td><td>Run migrations and seed database</td>
</tr>
<tr>
<td><code>php artisan test</code></td><td>Run all PHPUnit tests</td>
</tr>
<tr>
<td><code>npm install</code></td><td>Install node dependencies</td>
</tr>
<tr>
<td><code>npm run dev</code></td><td>Build frontend assets</td>
</tr>
<tr>
<td><code>docker-compose up -d</code></td><td>Start all Docker containers</td>
</tr>
<tr>
<td><code>docker exec -it nz-term-deposits-app bash</code></td><td>Enter app container shell</td>
</tr>
<tr>
<td><code>php artisan websockets:serve</code></td><td>Start websocket server</td>
</tr>
</table>

<hr>
<h2>License</h2>
<p>This project is open-source under the MIT License.</p>
<hr>
<h2>Acknowledgements</h2>
<ul>
	<li>Laravel Framework</li>
	<li>Laravel Jetstream &amp; Livewire</li>
	<li>BeyondCode Laravel Websockets</li>
	<li>Lighthouse GraphQL Server</li>
	<li>Maatwebsite Excel &amp; Barryvdh DomPDF Packages</li>
	<li>PhpMyAdmin for database management</li>
</ul>
<hr>
<h2>Contact</h2>
<p>For issues or contributions, please submit PRs or issues on GitHub.</p>

<p><small>Note: This app is not intended for financial advice, it is only to be used as a guide. Please consult a licensed financial adviser for any investment advice.</small></p>
</div>
</body>
</html>