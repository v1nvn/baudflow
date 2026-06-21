defmodule Baudflow.Notifications.Webhook do
  @moduledoc """
  Webhook channel (#24). POSTs the rendered payload as JSON to a user-configured
  URL — Home Assistant, Grafana, n8n, custom endpoints.

  Owns its transport config the way the Channel contract demands: the URL is a
  user-tunable `Settings` value (unlike ntfy's deploy-wired app env), and the
  channel is **enabled iff the URL is non-blank** (one "off" representation — no
  compensating enable flag, matching the escalated_cron / promised_* idioms). A
  hung endpoint never holds the worker's queue slot; a failure never raises. Test
  stubbing rides a `:webhook_plug` app-env entry, the same shape as `:ntfy_plug`
  (wiring, not a user-tunable value).
  """

  @behaviour Baudflow.Notifications.Channel

  require Logger

  alias Baudflow.Settings

  @impl true
  def send(body) do
    case Settings.get("webhook_url") do
      url when is_binary(url) and url != "" -> post(url, body)
      _ -> :ok
    end
  end

  defp post(url, body) do
    options =
      [
        url: url,
        method: :post,
        body: body,
        headers: [{"content-type", "application/json"}],
        receive_timeout: 5_000,
        connect_options: [timeout: 2_000]
      ]
      |> Kernel.++(plug_option())

    case Req.post(options) do
      {:ok, %Req.Response{status: status}} when status < 400 ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("webhook post returned non-success status: #{status}")
        :error

      {:error, exception} ->
        Logger.warning("webhook post failed: #{Exception.message(exception)}")
        :error
    end
  end

  defp plug_option do
    case Application.get_env(:baudflow, :webhook_plug) do
      nil -> []
      plug -> [plug: plug]
    end
  end
end
