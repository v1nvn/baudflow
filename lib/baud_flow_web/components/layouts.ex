defmodule BaudFlowWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BaudFlowWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders your app layout.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :active_page, :atom, default: nil, doc: "the current active page for nav highlighting"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="sticky top-0 z-40 bg-surface-0/90 backdrop-blur-md border-b border-border">
      <div class="flex items-center justify-between h-12 max-w-5xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <.link navigate={~p"/"} class="flex items-center gap-2">
            <div class="p-1 rounded-md bg-accent">
              <.icon name="hero-signal" class="size-3.5 text-white" />
            </div>
            <span class="text-sm font-bold tracking-tight text-text">BaudFlow</span>
          </.link>
        </div>
        <div class="flex items-center">
          <ul class="flex items-center gap-0.5 px-1">
            <li>
              <.link
                navigate={~p"/"}
                aria-label="Dashboard"
                class={[
                  "px-2.5 py-1 text-xs font-medium rounded-md transition-colors duration-150",
                  @active_page != :dashboard &&
                    "text-text-ghost hover:text-text-dim hover:bg-surface-3",
                  @active_page == :dashboard && "text-text bg-surface-3"
                ]}
              >
                <.icon name="hero-home-mini" class="size-3.5 inline-block mr-0.5" />
                <span class="hidden sm:inline">Dashboard</span>
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/history"}
                aria-label="History"
                class={[
                  "px-2.5 py-1 text-xs font-medium rounded-md transition-colors duration-150",
                  @active_page != :history && "text-text-ghost hover:text-text-dim hover:bg-surface-3",
                  @active_page == :history && "text-text bg-surface-3"
                ]}
              >
                <.icon name="hero-clock-mini" class="size-3.5 inline-block mr-0.5" />
                <span class="hidden sm:inline">History</span>
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/runs"}
                aria-label="Runs"
                class={[
                  "px-2.5 py-1 text-xs font-medium rounded-md transition-colors duration-150",
                  @active_page != :runs && "text-text-ghost hover:text-text-dim hover:bg-surface-3",
                  @active_page == :runs && "text-text bg-surface-3"
                ]}
              >
                <.icon name="hero-list-bullet-mini" class="size-3.5 inline-block mr-0.5" />
                <span class="hidden sm:inline">Runs</span>
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/settings"}
                aria-label="Settings"
                class={[
                  "px-2.5 py-1 text-xs font-medium rounded-md transition-colors duration-150",
                  @active_page != :settings &&
                    "text-text-ghost hover:text-text-dim hover:bg-surface-3",
                  @active_page == :settings && "text-text bg-surface-3"
                ]}
              >
                <.icon name="hero-cog-6-tooth-mini" class="size-3.5 inline-block mr-0.5" />
                <span class="hidden sm:inline">Settings</span>
              </.link>
            </li>
            <li class="ml-1.5 border-l border-border pl-1.5">
              <.theme_toggle />
            </li>
          </ul>
        </div>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-10 bg-surface-0 min-h-screen">
      <div class="mx-auto max-w-5xl space-y-8">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  Rendered as fixed-position toasts so they don't affect page layout.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="Connection lost"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle.
  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5 bg-surface-2 rounded-md p-0.5 border border-border">
      <button
        class="flex p-1 cursor-pointer rounded transition-colors [[data-theme=system]_&]:bg-accent [[data-theme=system]_&]:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        title="System theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-3.5 text-text-ghost" />
      </button>
      <button
        class="flex p-1 cursor-pointer rounded transition-colors [[data-theme=light]_&]:bg-accent [[data-theme=light]_&]:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light theme"
      >
        <.icon name="hero-sun-micro" class="size-3.5 text-text-ghost" />
      </button>
      <button
        class="flex p-1 cursor-pointer rounded transition-colors [[data-theme=dark]_&]:bg-accent [[data-theme=dark]_&]:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark theme"
      >
        <.icon name="hero-moon-micro" class="size-3.5 text-text-ghost" />
      </button>
    </div>
    """
  end
end
