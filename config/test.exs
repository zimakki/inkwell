import Config

# Disable BEAM shutdown when /stop is hit during tests.
config :inkwell, :shutdown_on_stop, false

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
