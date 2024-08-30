defmodule Mix.Tasks.TrainModel do
  @moduledoc """
  Given a CSV file of EtaMonitor logs, trains the XGBoost model used for internal predictions.

  Options:
  --validate: whether to return a validation score instead of fully training the model
  --seed <integer>: value to use for randomiziation (default: randomized)

  Splunk query:
  ```
  index=<index> EtaMonitor time pick_lat status!=closed route > 0
  | sort 0 route, -time
  | eval noon=strftime(_time - 10800, "%Y-%m-%dT12:00:00%z")
  | table time,trip_id,route,status,noon,promise,pick,ors_duration,load_time,pick_lat,pick_lon,pick_order
  ```
  """

  require Explorer.DataFrame, as: DF
  alias Explorer.{Duration, Series}
  alias RideAlong.EtaCalculator.Model

  def run(opts) do
    {parsed, [file_name | _], _} =
      OptionParser.parse(opts,
        strict: [validate: :boolean, seed: :integer]
      )

    df =
      file_name
      |> DF.from_csv!(
        parse_dates: true,
        nil_values: [""],
        dtypes: %{status: :category}
      )
      |> DF.filter(route > 0)

    arrival_times = arrival_times(df)

    df =
      df
      |> DF.join(arrival_times, on: "trip_id")
      |> DF.filter(arrival_time > time)
      |> DF.filter(status in ["enroute", "waiting"])
      |> DF.mutate(
        time_of_day: time - noon,
        day_of_week: Series.day_of_week(noon),
        ors_duration: Series.fill_missing(ors_duration, -1),
        promise_duration: diff_seconds(promise, time),
        pick_duration: diff_seconds(pick, time),
        actual_duration: diff_seconds(arrival_time, time),
        waiting?: select(status == "waiting", 1, 0)
      )
      |> DF.filter(actual_duration < 7200)
      |> DF.mutate(
        ors_to_add: select(actual_duration > ors_duration, actual_duration - ors_duration, 0)
      )

    training_fields = Model.feature_names()

    seed = parsed[:seed] || Enum.random(0..(Integer.pow(2, 32) - 1))

    df = DF.shuffle(df, seed: seed)

    size = Series.size(df[:time])
    validation_size = min(trunc(size * 0.9), 10_000)

    train_df =
      if parsed[:validate] do
        DF.slice(df, validation_size..-1//1)
      else
        df
      end

    x =
      train_df
      |> DF.select(training_fields)
      |> Nx.stack(axis: 1)

    y = DF.select(train_df, :ors_to_add) |> Nx.concatenate()

    opts = [
      booster: :gbtree,
      device: :cuda,
      objective: :reg_absoluteerror,
      tree_method: :approx,
      max_depth: 5,
      num_boost_rounds: 100,
      subsample: 0.75,
      colsample_bynode: 0.9,
      learning_rate: 0.3,
      feature_name: training_fields,
      seed: seed
    ]

    IO.puts("About to train (using seed #{seed})...")
    model = EXGBoost.train(x, y, opts)
    IO.puts("Trained!")

    if parsed[:validate] do
      IO.puts("Validating model...")

      validate_df =
        df
        |> DF.slice(0..(validation_size - 1))

      x =
        validate_df
        |> DF.select(training_fields)
        |> Nx.stack(axis: 1)

      pred = EXGBoost.predict(model, x, feature_name: training_fields)

      overall =
        (validate_df
         |> DF.put(:add, Nx.as_type(pred, :s32))
         |> DF.mutate(
           regression:
             time + %Duration{value: 1_000, precision: :millisecond} * (add + ors_duration)
         )
         |> overall_accuracy(:time, :arrival_time, :regression, &accuracy/1))[:accuracy][0]

      IO.puts("Overall accuracy: #{overall}%")
    else
      EXGBoost.write_model(model, Model.model_path(), overwrite: true, format: :ubj)
      IO.puts("Wrote model!")

      IO.puts("Not validating: use `--validate` to set aside some data for validation.")
    end

    :ok
  end

  defp arrival_times(df) do
    grouped = DF.group_by(df, :trip_id)

    pure_arrival_times =
      grouped
      |> DF.filter(status == "arrived")
      |> DF.summarise(pure_arrival_time: Series.min(time))

    pickup_arrival_times =
      grouped
      |> DF.filter(status == "picked_up")
      |> DF.mutate(load_time: load_time * %Duration{value: 60_000, precision: :millisecond})
      |> DF.mutate(time: time - load_time)
      |> DF.summarise(pickup_arrival_time: Series.min(time))

    arrival_times =
      df
      |> DF.distinct([:trip_id])
      |> DF.join(pure_arrival_times, how: :left, on: :trip_id)
      |> DF.join(pickup_arrival_times, how: :left, on: :trip_id)
      |> DF.mutate(
        arrival_time: select(is_nil(pure_arrival_time), pickup_arrival_time, pure_arrival_time)
      )
      |> DF.select([:trip_id, :arrival_time])
      |> DF.filter(not is_nil(arrival_time))

    arrival_times
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
    |> DF.filter(category != "30+")
    |> DF.group_by(:category)
    |> DF.summarise(
      size: size(accurate?),
      accurate_count: sum(accurate?)
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
    |> DF.mutate(accurate?: diff >= ^binned[:allowed_early] and diff <= ^binned[:allowed_late])
  end

  defp accuracy(series) do
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
  @dialyzer {:nowarn_function, run: 1, overall_accuracy: 5, grouped_accuracy: 5}
end
