defmodule RideAlong.WebhookPublisher do
  @moduledoc """
  Server which makes webhook requests based on notifications from RiderNotifier.

  The webhooks are stored as a map in the configuration of URL => secret.

  The secret is used to generate an SHA256 HMAC signature for the recipient to validate.
  """
  use GenServer
  require Logger

  alias RideAlong.Adept

  @gregorian_date_epoch Date.to_gregorian_days(~D[2024-08-01])

  @default_name __MODULE__

  def start_link(opts) do
    if opts[:start] do
      name = Keyword.get(opts, :name, @default_name)
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      :ignore
    end
  end

  defstruct [:secret, :url_generator_mfa, webhooks: %{}]
  @impl GenServer
  def init(opts) do
    state = struct(__MODULE__, opts)
    RideAlong.PubSub.subscribe("notification:trip")
    {:ok, state}
  end

  @impl GenServer
  def handle_info({:trip_notification, %Adept.Trip{} = trip}, state) do
    {mod, fun, args} = state.url_generator_mfa

    case apply(mod, fun, [trip.trip_id | args]) do
      {:ok, url} ->
        send_trip_notification(state, trip, url)

      :error ->
        :ok
    end

    {:noreply, state}
  end

  def send_trip_notification(state, trip, url) do
    now = DateTime.shift_zone!(DateTime.utc_now(), Application.get_env(:ride_along, :time_zone))

    vehicle = Adept.get_vehicle_by_route(trip.route_id)
    status = Adept.Trip.status(trip, vehicle, now)

    notification_hash =
      :erlang.phash2(
        {
          # fields that if they changed, we'd want to re-send a notification
          state.secret,
          trip.date,
          trip.trip_id,
          trip.route_id,
          status in [:arrived, :picked_up]
        },
        # 2 ** 24
        16_777_216
      )

    <<notification_id::integer-40>> = <<
      Date.to_gregorian_days(trip.date) - @gregorian_date_epoch::integer-16,
      notification_hash::integer-24
    >>

    data =
      Jason.encode_to_iodata!(%{
        now: now,
        tripId: trip.trip_id,
        routeId: trip.route_id,
        clientId: trip.client_id,
        etaTime: trip.pick_time,
        promiseTime: trip.promise_time,
        status: status |> Atom.to_string() |> String.upcase(),
        url: url,
        notificationId: notification_id
      })

    for {webhook_url, webhook_secret} <- state.webhooks do
      request = webhook_request(webhook_url, webhook_secret, data)
      Logger.debug(inspect(request))
      {_, response} = Req.run(request)

      {result, error} =
        case response do
          %{status: two_xx} when two_xx >= 200 and two_xx < 300 ->
            {:ok, nil}

          _ ->
            {:error, inspect(response)}
        end

      Logger.info(
        "#{__MODULE__} post trip_id=#{trip.trip_id} notification_id=#{notification_id} result=#{result} error=#{error}"
      )
    end
  end

  def webhook_request(url, secret, body) do
    signature =
      :hmac
      |> :crypto.mac(:sha256, secret, body)
      |> Base.encode16()
      |> String.downcase()

    Req.new(
      method: :post,
      url: url,
      headers: [
        content_type: "application/json",
        x_signature_256: "sha256=" <> signature
      ],
      body: body,
      decode_body: false,
      retry: :transient
    )
  end
end
