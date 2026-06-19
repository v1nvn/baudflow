defmodule Baudflow.Notifications.Channel do
  @moduledoc """
  Behaviour for a notification transport (`Ntfy` today; `Webhook` in #24).

  A channel takes an already-rendered message and delivers it. Rendering is the
  template layer's job; the channel owns only its transport config and POST.
  """

  @callback send(message :: String.t()) :: :ok | :error
end
