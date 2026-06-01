defmodule BaudFlow.Repo do
  use Ecto.Repo,
    otp_app: :baud_flow,
    adapter: Ecto.Adapters.Postgres
end
