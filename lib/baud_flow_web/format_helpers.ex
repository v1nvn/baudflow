defmodule BaudFlowWeb.FormatHelpers do
  @moduledoc """
  Display formatting helpers available in all templates.
  """

  @doc "Format bytes into human-readable string (e.g. 100.0 MB, 1.50 GB)."
  def format_bytes(bytes) when is_integer(bytes) and bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 2)} GB"
  end

  def format_bytes(bytes) when is_integer(bytes) and bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 2)} MB"
  end

  def format_bytes(bytes) when is_integer(bytes) and bytes >= 1_024 do
    "#{Float.round(bytes / 1_024, 1)} KB"
  end

  def format_bytes(bytes) when is_integer(bytes), do: "#{bytes} B"
  def format_bytes(_), do: "--"

  @doc "Format milliseconds into human-readable duration (e.g. 12.3 s, 450 ms)."
  def format_duration_ms(ms) when is_integer(ms) and ms >= 1000 do
    "#{Float.round(ms / 1000, 1)} s"
  end

  def format_duration_ms(ms) when is_integer(ms), do: "#{ms} ms"
  def format_duration_ms(_), do: "--"

  @doc "Format raw bandwidth (bytes/sec) into human-readable string."
  def format_bandwidth(bw) when is_integer(bw) and bw >= 1_000_000 do
    "#{Float.round(bw / 1_000_000, 2)} MB/s"
  end

  def format_bandwidth(bw) when is_integer(bw) and bw >= 1_000 do
    "#{Float.round(bw / 1_000, 2)} KB/s"
  end

  def format_bandwidth(bw) when is_integer(bw), do: "#{bw} B/s"
  def format_bandwidth(_), do: "--"
end
