import Config

config :inkwell, Inkwell.Repo,
  database: Path.join(__DIR__, "../path/to/your#{System.get_env("MIX_TEST_PARTITION")}.db"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Disable BEAM shutdown when /stop is hit during tests.
config :inkwell, :shutdown_on_stop, false

# Use a stub module for file dialogs in tests (avoids actual osascript calls).
config :inkwell, :file_dialog_module, InkwellWeb.FileDialogControllerTest.Stub

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :inkwell, InkwellWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "c0kn5lKlaSP3jSlJc5+DFP5L1gMytN35cIihWxsAv6YAA//Av2LbqWU1IiHqfmvH",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
