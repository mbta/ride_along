defmodule RideAlong.EtaCalculator.Training do
  @moduledoc """
  Private module to support model training.
  """

  require Explorer.DataFrame, as: DF
  alias Explorer.{Duration, Series}
  alias RideAlong.EtaCalculator.Model

  def training_params do
    [
      booster: :gbtree,
      device: :cuda,
      objective: :reg_absoluteerror,
      eval_metric: :mae,
      tree_method: :approx,
      seed: 1_111_534_962,
      max_depth: 7,
      num_boost_rounds: 94,
      max_bin: 512,
      subsample: 0.75,
      colsample_bynode: 0.9,
      learning_rates: fn _ -> 0.1 end,
      verbose_eval: false,
      feature_name: Model.feature_names()
    ]
  end

  def populate(df) do
    df
    |> DF.filter(arrival_time > time)
    |> DF.filter(status in ["enroute", "waiting"])
    |> DF.mutate(
      time_of_day: diff_seconds(time, noon),
      day_of_week: Series.day_of_week(noon),
      ors_duration: Series.fill_missing(ors_duration, -1),
      vehicle_speed: Series.fill_missing(vehicle_speed, -1),
      promise_duration: diff_seconds(promise, time),
      pick_duration: diff_seconds(pick, time),
      actual_duration: diff_seconds(arrival_time, time),
      waiting?: select(status == "waiting", 1, 0),
      ors_distance: Series.fill_missing(ors_distance, -1)
    )
    |> DF.filter(actual_duration < 7200)
    |> DF.mutate(
      pick_offset: pick_duration - promise_duration,
      heading_offset:
        select(
          not is_nil(ors_heading) and not is_nil(vehicle_heading) and ors_heading != -1 and
            vehicle_heading != -1,
          abs(ors_heading - vehicle_heading),
          -1
        ),
      ors_to_add: select(actual_duration > ors_duration, actual_duration - ors_duration, 0)
    )
  end

  def predict_from_data_frame(model, df) do
    slice_size = 25_000
    size = Series.size(df[:time])
    slices = div(size, slice_size)

    slices =
      case rem(size, slice_size) do
        0 -> slices - 1
        _ -> slices
      end

    for slice <- 0..slices do
      Model.predict_from_tensor(
        model,
        df
        |> DF.select(Model.feature_names())
        |> DF.slice((slice * slice_size)..((slice + 1) * slice_size - 1))
        |> Nx.stack(axis: 1)
      )
      |> Series.from_tensor()
    end
    |> Series.concat()
  end

  def arrival_times(df) do
    group = [:trip_id, :route]
    grouped = DF.group_by(df, group)

    pure_arrival_times =
      grouped
      |> DF.filter(status == "arrived")
      |> DF.summarise(
        pure_promise_time: Series.min(promise),
        pure_arrival_time: Series.min(time)
      )

    pickup_arrival_times =
      grouped
      |> DF.filter(status == "picked_up")
      |> DF.mutate(load_time: load_time * %Duration{value: 60_000, precision: :millisecond})
      |> DF.mutate(time: time - load_time)
      |> DF.summarise(
        pickup_promise_time: Series.min(promise),
        pickup_arrival_time: Series.min(time),
        pickup_arrival_adept: Series.min(pickup_arrival)
      )

    arrival_times =
      df
      |> DF.distinct(group)
      |> DF.join(pure_arrival_times, how: :left, on: group)
      |> DF.join(pickup_arrival_times, how: :left, on: group)
      |> DF.mutate(
        promise_time: select(is_nil(pure_promise_time), pickup_promise_time, pure_promise_time),
        arrival_time: select(is_nil(pure_arrival_time), pickup_arrival_time, pure_arrival_time)
      )
      |> DF.mutate(
        arrival_duration: diff_seconds(arrival_time, promise_time),
        pickup_arrival_adept_duration: diff_seconds(arrival_time, pickup_arrival_adept)
      )
      |> DF.mutate(on_time?: arrival_duration < 900)

    on_time_performance =
      Float.round(
        100 * Series.sum(arrival_times[:on_time?]) / Series.count(arrival_times[:on_time?]),
        1
      )

    IO.puts("On-time performance: #{on_time_performance}%")

    arrival_times
    |> DF.filter(
      not is_nil(arrival_time) and
        abs(pickup_arrival_adept_duration) <= 60
    )
    |> DF.select(group ++ [:arrival_time])
  end

  def overall_accuracy(df, time_col, actual_col, prediction_col, accuracy) do
    df
    |> grouped_accuracy(time_col, actual_col, prediction_col, accuracy)
    |> DF.summarise(accuracy: round(mean(accuracy), 1))
  end

  def grouped_accuracy(df, time_col, actual_col, prediction_col, accuracy) do
    df
    |> DF.distinct([time_col, actual_col, prediction_col])
    |> with_accuracy(time_col, actual_col, prediction_col, accuracy)
    |> DF.filter(category != "15+" and category != "30+" and category != "40+")
    |> DF.group_by(:category)
    |> DF.summarise(
      size: size(accurate?),
      accurate_count: sum(accurate?),
      early_count: sum(early?),
      late_count: sum(late?)
    )
    |> DF.mutate(accuracy: round(100 * cast(accurate_count, {:u, 32}) / size, 1))
    |> DF.ungroup()
    |> DF.sort_by(asc: category)
  end

  def with_accuracy(df, time_col, actual_col, prediction_col, accuracy) do
    time_ahead_seconds = diff_seconds(df[actual_col], df[time_col])
    diff_seconds = diff_seconds(df[prediction_col], df[actual_col])
    binned = accuracy.(time_ahead_seconds)

    df
    |> DF.put(:diff, diff_seconds)
    |> DF.put(:category, binned[:category])
    |> DF.mutate(early?: diff < ^binned[:allowed_early], late?: diff > ^binned[:allowed_late])
    |> DF.mutate(accurate?: not early? and not late?)
  end

  def accuracy(series) do
    cat =
      series
      |> Explorer.Series.cut([3 * 60, 6 * 60, 12 * 60, 30 * 60],
        labels: ["0-3", "3-6", "6-12", "12-30", "30+"]
      )

    bins =
      DF.new(
        %{
          category: ["0-3", "3-6", "6-12", "12-30", "30+"],
          allowed_early: [-60, -90, -150, -240, -330],
          allowed_late: [60, 120, 210, 360, 510]
        },
        dtypes: %{
          category: :category,
          allowed_early: {:s, 16},
          allowed_late: {:u, 16}
        }
      )

    cat
    |> DF.join(bins, how: :left, on: :category)
  end

  def transit_app_accuracy(series) do
    cat =
      series
      |> Explorer.Series.cut([3 * 60, 6 * 60, 10 * 60, 15 * 60],
        labels: ["0-3", "3-6", "6-10", "10-15", "15+"]
      )

    bins =
      DF.new(
        %{
          category: ["0-3", "3-6", "6-10", "10-15", "15+"],
          allowed_early: [-30, -60, -60, -90, -120],
          allowed_late: [90, 150, 210, 270, 330]
        },
        dtypes: %{
          category: :category,
          allowed_early: {:s, 16},
          allowed_late: {:u, 16}
        }
      )

    DF.join(cat, bins, how: :left, on: :category)
  end

  def larger_bins_accuracy(series) do
    cat =
      series
      |> Explorer.Series.cut([5 * 60, 10 * 60, 20 * 60, 40 * 60],
        labels: ["0-5", "5-10", "10-20", "20-40", "40+"]
      )

    bins =
      DF.new(
        %{
          category: ["0-5", "5-10", "10-20", "20-40", "40+"],
          allowed_early: [-90, -150, -240, -300, -360],
          allowed_late: [90, 180, 300, 420, 540]
        },
        dtypes: %{
          category: :category,
          allowed_early: {:s, 16},
          allowed_late: {:u, 16}
        }
      )

    cat
    |> DF.join(bins, how: :left, on: :category)
  end

  def on_time_performance_accuracy(series) do
    cat =
      series
      |> Explorer.Series.cut([5 * 60, 10 * 60, 20 * 60, 40 * 60],
        labels: ["0-5", "5-10", "10-20", "20-40", "40+"]
      )

    bins =
      DF.new(
        %{
          category: ["0-5", "5-10", "10-20", "20-40", "40+"],
          allowed_early: [-300, -300, -300, -300, -300],
          allowed_late: [900, 900, 900, 900, 900]
        },
        dtypes: %{
          category: :category,
          allowed_early: {:s, 16},
          allowed_late: {:u, 16}
        }
      )

    cat
    |> DF.join(bins, how: :left, on: :category)
  end

  def duration_to_seconds(col) do
    Series.cast(
      Series.divide(
        Series.cast(col, :integer),
        1_000_000
      ),
      :integer
    )
  end

  def diff_seconds(first, second) do
    duration_to_seconds(Series.subtract(first, second))
  end

  # these functions work, but the DF.summarize/2 macro confuses Dialyzer
  @dialyzer {:nowarn_function, overall_accuracy: 5, grouped_accuracy: 5}
end
