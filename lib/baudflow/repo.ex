defmodule Baudflow.Repo do
  use Ecto.Repo,
    otp_app: :baudflow,
    adapter: Ecto.Adapters.Postgres
end
