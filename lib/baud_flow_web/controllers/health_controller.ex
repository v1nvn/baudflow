defmodule BaudFlowWeb.HealthController do
  use BaudFlowWeb, :controller

  def check(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
