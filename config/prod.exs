import Config

config :inkwell, InkwellWeb.Endpoint,
  cache_static_manifest: "priv/phx_static/cache_manifest.json"

config :logger, level: :info
