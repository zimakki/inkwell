import Config

if System.get_env("PHX_SERVER") do
  config :inkwell, InkwellWeb.Endpoint, server: true
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      (
        path = Path.join(System.user_home!(), ".inkwell/secret")

        if File.exists?(path) do
          File.read!(path)
        else
          secret = :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, secret)
          File.chmod!(path, 0o600)
          secret
        end
      )

  config :inkwell, InkwellWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: 0],
    # Daemon binds a random port (port: 0) and the configured url: host:
    # localhost has no port, so the default origin check would reject the
    # browser's Origin header. Allow any port on loopback hosts.
    check_origin: ["//localhost", "//localhost:*", "//127.0.0.1", "//127.0.0.1:*"],
    secret_key_base: secret_key_base,
    server: true

  inkwell_home = Path.join(System.user_home!(), ".inkwell")
  File.mkdir_p!(inkwell_home)

  config :inkwell, Inkwell.Repo,
    database: Path.join(inkwell_home, "inkwell.db"),
    pool_size: 5,
    journal_mode: :wal
end
