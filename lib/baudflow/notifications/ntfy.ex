defmodule Baudflow.Notifications.Ntfy do
  @moduledoc """
  ntfy.sh channel. Owns its transport config (URL/topic from app env — deploy
  wiring, not user-tunable) and the `Req.post` with hard timeouts. A hung ntfy
  must not hold the worker's queue slot; a failure never raises.
  """

  @behaviour Baudflow.Notifications.Channel

  require Logger

  @impl true
  def send(message) do
    ntfy_url = Application.get_env(:baudflow, :ntfy_url, "http://ntfy-svc.ntfy")
    ntfy_topic = Application.get_env(:baudflow, :ntfy_topic, "baudflow")
    post(ntfy_url, ntfy_topic, message)
  end

  defp post(url, topic, message) do
    options =
      [
        url: "#{url}/#{topic}",
        method: :post,
        body: message,
        headers: [{"Title", "Baudflow Alert"}, {"Priority", "high"}],
        receive_timeout: 5_000,
        connect_options: [timeout: 2_000]
      ]
      |> Kernel.++(plug_option())

    case Req.post(options) do
      {:ok, %Req.Response{status: status}} when status < 400 ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("ntfy post returned non-success status: #{status}")
        :error

      {:error, exception} ->
        Logger.warning("ntfy post failed: #{Exception.message(exception)}")
        :error
    end
  end

  defp plug_option do
    case Application.get_env(:baudflow, :ntfy_plug) do
      nil -> []
      plug -> [plug: plug]
    end
  end
end
