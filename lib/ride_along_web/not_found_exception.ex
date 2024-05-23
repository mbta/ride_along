defmodule RideAlongWeb.NotFoundException do
  defexception []

  @impl Exception
  def exception(_) do
    %__MODULE__{}
  end

  @impl Exception
  def message(_) do
    "404 Not Found"
  end

  defimpl Plug.Exception do
    def actions(_) do
      []
    end

    def status(_) do
      :not_found
    end
  end
end
