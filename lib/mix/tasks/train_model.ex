defmodule Mix.Tasks.TrainModel do
  @moduledoc """
  Given a CSV file of EtaMonitor logs, trains the XGBoost model used for internal predictions.

  Options:
  --validate: whether to return a validation score instead of fully training the model
  --seed <integer>: value to use for randomization (or 0 to pick a random one)
  --max-depth <integer>: how deep to create trees
  --num-boost-rounds: how many rounds to boost
  --num-parallel-trees: how many trees to make during each iteration
  --tree-method: method for generating trees (approx, hist, exact)

  There's a Splunk report (EtaMonitor results) which can generate a CSV in the right format.
  """

  require Explorer.DataFrame, as: DF
  alias Explorer.{Duration, Series}
  alias RideAlong.EtaCalculator.Model
  import RideAlong.EtaCalculator.Training

  def run(opts) do
    {parsed, [_ | _] = file_names, _} =
      OptionParser.parse(opts,
        strict: [
          validate: :boolean,
          replan: :boolean,
          seed: :integer,
          max_depth: :integer,
          num_boost_rounds: :integer,
          num_parallel_trees: :integer,
          tree_method: :string
        ]
      )

    training_fields = Model.feature_names()

    df =
      file_names
      |> Enum.map(fn file_name ->
        df =
          file_name
          |> DF.from_csv!(
            parse_dates: true,
            nil_values: [""],
            dtypes: %{status: :category, vehicle_speed: {:f, 32}}
          )
          |> DF.filter(route > 0)

        df =
          if parsed[:replan] do
            Application.ensure_all_started(:req)
            df = recalculate_eta(df)
            IO.puts("Replanned; writing data back to #{file_name}...")
            DF.to_csv!(df, file_name)
            df
          else
            df
          end

        arrival_times = arrival_times(df)

        df = DF.join(df, arrival_times, on: [:trip_id, :route])

        df
        |> populate()
        |> DF.select(training_fields ++ [:time, :ors_to_add, :arrival_time])
      end)
      |> DF.concat_rows()

    df = DF.sort_by(df, asc: time)

    size = Series.size(df[:time])
    validation_size = min(trunc(size * 0.1), 25_000)
    train_size = size - validation_size

    train_df =
      if parsed[:validate] do
        DF.slice(df, 0..(train_size - 1))
      else
        df
      end

    validate_df =
      df
      |> DF.slice(train_size..size)

    x =
      train_df
      |> DF.select(training_fields)
      |> Nx.stack(axis: 1)

    y = DF.select(train_df, :ors_to_add) |> Nx.concatenate()

    opts = training_params_from_opts(parsed, training_params(), validate_df)

    IO.puts("About to train...")
    {timing, model} = :timer.tc(EXGBoost, :train, [x, y, opts], :millisecond)

    model =
      if model.best_iteration < opts[:num_boost_rounds] do
        %{model | best_iteration: model.best_iteration - opts[:early_stopping_rounds] - 1}
      else
        model
      end

    IO.puts("Trained! (in #{Float.round(timing / 1000.0, 1)}s)")
    IO.puts(inspect(model))

    size_mb =
      Float.round(byte_size(EXGBoost.dump_model(model, format: :ubj)) / 1024.0 / 1024.0, 1)

    IO.puts("Model size: #{size_mb} MB")

    if parsed[:validate] do
      IO.puts("Training options:")

      opts
      |> Keyword.drop([:evals, :early_stopping_rounds, :feature_name])
      |> Keyword.put(:num_boost_rounds, model.best_iteration)
      |> inspect(pretty: true)
      |> IO.puts()

      IO.puts("Validating model...")

      pred = predict_from_data_frame(model, validate_df)

      overall =
        (validate_df
         |> DF.mutate(regression: time + %Duration{value: 1_000, precision: :millisecond} * ^pred)
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

  defp training_params_from_opts(opts, acc, validate_df) do
    _tree_methods = [:exact, :approx, :hist]

    Enum.reduce(opts, acc, fn
      {:seed, 0}, acc ->
        Keyword.put(acc, :seed, Enum.random(0..(Integer.pow(2, 32) - 1)))

      {:seed, seed}, acc ->
        Keyword.put(acc, :seed, seed)

      {:num_boost_rounds, rounds}, acc ->
        Keyword.put(acc, :num_boost_rounds, rounds)

      {:num_parallel_trees, rounds}, acc ->
        Keyword.put(acc, :num_parallel_trees, rounds)

      {:max_depth, depth}, acc ->
        Keyword.put(acc, :max_depth, depth)

      {:tree_method, method}, acc ->
        Keyword.put(acc, :tree_method, String.to_existing_atom(method))

      {:validate, _}, acc ->
        x =
          validate_df
          |> DF.select(Model.feature_names())
          |> Nx.stack(axis: 1)

        y = validate_df |> DF.select(:ors_to_add) |> Nx.concatenate()

        Keyword.merge(acc,
          early_stopping_rounds: 10,
          evals: [{x, y, "validate"}]
        )

      _, acc ->
        acc
    end)
  end

  defp recalculate_eta(df) do
    empty = %{lat: nil, lon: nil}

    new_cols =
      df
      |> DF.select([:pick_lat, :pick_lon, :vehicle_lat, :vehicle_lon])
      |> DF.to_rows()
      |> Task.async_stream(
        fn row ->
          source = %{lat: row["vehicle_lat"], lon: row["vehicle_lon"]}
          destination = %{lat: row["pick_lat"], lon: row["pick_lon"]}

          with true <- source != empty,
               true <- destination != empty,
               {:ok, route} <- RideAlong.OpenRouteService.directions(source, destination) do
            %{
              ors_duration: route.duration,
              ors_heading: route.bearing,
              ors_distance: route.distance
            }
          else
            _ ->
              %{ors_duration: -1, ors_heading: -1, ors_distance: -1}
          end
        end,
        max_concurrency: System.schedulers_online() * 4,
        ordered: true
      )
      |> Enum.map(fn {:ok, val} -> val end)
      |> DF.new()

    df
    |> DF.discard([:ors_duration, :ors_heading, :ors_distance])
    |> DF.concat_columns(new_cols)
  end
end
