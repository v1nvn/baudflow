defmodule Baudflow.Test.TcpListener do
  @moduledoc """
  Tiny test helper: a loopback TCP listener on an OS-assigned ephemeral port.

  Lets the Ping runner tests exercise `:gen_tcp.connect/4` against a real,
  deterministic localhost target instead of a mock. `start/0` returns a port
  clients can connect to - the kernel completes the handshake into the listen
  backlog without anyone calling accept, so `connect/4` returns successfully.
  `closed_port/0` binds then immediately closes, handing back a port that
  refuses connections (for the all-attempts-fail path).
  """

  def start do
    {:ok, listen} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, active: false)
    {:ok, port} = :inet.port(listen)
    {port, listen}
  end

  def stop(listen), do: :gen_tcp.close(listen)

  def closed_port do
    {:ok, listen} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, active: false)
    {:ok, port} = :inet.port(listen)
    :gen_tcp.close(listen)
    port
  end
end
