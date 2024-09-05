defmodule RideAlong.EtaCalculator.Model do
  @moduledoc """
  Gradient-Boosted Forest (XGBoost) model for ETA predictions.
  """
  @feature_names [
    "route",
    "ors_duration",
    "promise_duration",
    "pick_duration",
    "time_of_day",
    "day_of_week",
    "pick_lat",
    "pick_lon",
    "pick_order"
  ]
  def start_link(opts) do
    if opts[:start] do
      :persistent_term.put(__MODULE__, read_model())
    end

    :ignore
  end

  def model do
    :persistent_term.get(__MODULE__)
  end

  def predict(trip, vehicle, route, now) do
    ors_duration =
      if route do
        route.duration
      else
        -1
      end

    noon = %{now | hour: 12, minute: 0, second: 0, microsecond: {0, 0}}

    tensor =
      Nx.tensor([
        [
          trip.route_id,
          ors_duration,
          DateTime.diff(trip.promise_time, now, :second),
          DateTime.diff(trip.pick_time, now, :second),
          DateTime.diff(now, noon, :second),
          Date.day_of_week(noon, :monday),
          Decimal.to_float(trip.lat),
          Decimal.to_float(trip.lon),
          trip.pick_order
        ]
      ])

    predicted =
      model()
      |> predict_from_tensor(tensor)
      |> Nx.sum()
      |> Nx.max(0)
      |> Nx.add(ors_duration)
      |> Nx.max(0)
      |> Nx.to_number()

    to_add = trunc(predicted * 1000)

    origin_time =
      if vehicle && vehicle.timestamp do
        vehicle.timestamp
      else
        now
      end

    DateTime.add(origin_time, to_add, :millisecond)
  end

  def predict_from_tensor(model, tensor) do
    EXGBoost.predict(model, tensor, feature_name: @feature_names)
  end

  def read_model do
    EXGBoost.read_model(model_path() <> ".ubj")
  end

  def model_path do
    Path.join(:code.priv_dir(:ride_along), "model")
  end

  def feature_names do
    @feature_names
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end
end
