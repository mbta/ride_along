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
  import RideAlong.EtaCalculator.Training

  def run(opts) do
    {parsed, [file_name | _], _} =
      OptionParser.parse(opts,
        strict: [
          validate: :boolean,
          seed: :integer,
          max_depth: :integer,
          num_boost_rounds: :integer,
          tree_method: :string
        ]
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
      |> populate()

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

    opts =
      Keyword.merge(
        training_params(),
        [seed: seed] ++ training_params_from_opts(parsed)
      )

    IO.puts("About to train (using seed #{seed})...")
    {timing, model} = :timer.tc(EXGBoost, :train, [x, y, opts], :millisecond)
    IO.puts("Trained! (in #{Float.round(timing / 1000.0, 1)}s)")

    size_mb =
      Float.round(byte_size(EXGBoost.dump_model(model, format: :ubj)) / 1024.0 / 1024.0, 1)

    IO.puts("Model size: #{size_mb} MB")

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
         |> overall_accuracy(:time, :arrival_time, :regression, &accuracy/1))[
          :accuracy
        ][0]

      IO.puts("Overall accuracy: #{overall}%")
    else
      EXGBoost.write_model(model, Model.model_path(), overwrite: true, format: :ubj)
      IO.puts("Wrote model!")

      IO.puts("Not validating: use `--validate` to set aside some data for validation.")
    end

    :ok
  end

  defp training_params_from_opts(opts) do
    _tree_methods = [:exact, :approx, :hist]

    Enum.reduce(opts, [], fn
      {:num_boost_rounds, rounds}, acc ->
        [num_boost_rounds: rounds] ++ acc

      {:max_depth, depth}, acc ->
        [max_depth: depth] ++ acc

      {:tree_method, method}, acc ->
        [tree_method: String.to_existing_atom(method)] ++ acc

      _, acc ->
        acc
    end)
  end
end
