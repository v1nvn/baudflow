defmodule BaudflowWeb.HealthController do
  use BaudflowWeb, :controller

  def check(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
