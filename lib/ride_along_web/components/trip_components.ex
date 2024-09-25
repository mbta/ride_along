defmodule RideAlongWeb.TripComponents do
  @moduledoc """
  Components used by RideAlongWeb.TripLive
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  import RideAlongWeb.CoreComponents
  use Gettext, backend: RideAlongWeb.Gettext

  attr :id, :string
  attr :flash, :map, default: %{}
  attr :kind, :atom, values: [:warning, :error]
  attr :rest, :global

  slot :inner_block

  def trip_flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "trip-flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={
        JS.push("lv:clear-flash", value: %{key: @kind})
        |> hide("##{@id}")
        |> JS.remove_class("flash-visible", to: "main")
      }
      phx-mounted={JS.add_class("flash-visible", to: "main")}
      role="alert"
      aria-atomic="true"
      class="rounded-t-xl p-4 bg-yellow-300 text-slate-600 text-xl"
      {@rest}
    >
      <div class="flex flex-row group">
        <div class="text-center flex-auto"><%= msg %></div>
        <button type="button" class="flex-none" aria-label={gettext("close")}>
          <span aria-hidden="true">
            <.icon
              name="hero-x-mark-solid"
              class="h-5 w-5 opacity-40 sm:opacity-70 group-hover:opacity-70"
            />
          </span>
        </button>
      </div>
    </div>
    """
  end

  attr :flash, :map, required: true

  def trip_flash_group(assigns) do
    ~H"""
    <.trip_flash kind={:warning} flash={@flash} />
    <.trip_flash kind={:error} flash={@flash} />
    <.trip_flash
      id="network-error"
      kind={:error}
      phx-disconnected={
        show("#network-error")
        |> JS.add_class("flash-visible", to: "main")
      }
      phx-connected={hide("#network-error") |> JS.remove_class("flash-visible", to: "main")}
      hidden
    >
      <.icon name="hero-signal-slash" class="h-4 w-4" />
      <%= gettext("Live updates are temporarily unavailable.") %>
    </.trip_flash>
    """
  end

  attr :text, :string, required: true

  def linkify_phone(assigns) do
    ~H"""
    <% [first | rest] = Regex.split(~r|\d{3}-\d{3}-\d{4}|, assigns[:text], include_captures: true) %>
    <%= first %>
    <span :for={[phone, after_phone] <- Enum.chunk_every(rest, 2)}>
      <.link class="underline" href={"tel:" <> phone}><%= phone %></.link>
      <%= after_phone %>
    </span>
    """
  end

  attr :id, :string, required: true
  attr :src, :string, required: true
  attr :rest, :global

  def hidden_image(assigns) do
    ~H"""
    <img
      class="absolute -top-full -left-full"
      aria-hidden="true"
      phx-track-static
      id={@id}
      src={@src}
      integrity={RideAlongWeb.Endpoint.static_integrity(@src)}
      {@rest}
    />
    """
  end

  attr :title, :string, required: true
  attr :value, :any, default: []
  attr :rest, :global
  slot :inner_block, default: []

  def labeled_field(assigns) do
    ~H"""
    <div {@rest}>
      <span class="font-bold"><%= @title %>:</span> <%= @value %><%= render_slot(@inner_block) %>
    </div>
    """
  end
end
