defmodule RideAlong.WebhookPublisherTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Plug.Conn
  alias RideAlong.Adept
  alias RideAlong.AdeptFixtures
  alias RideAlong.PubSub
  alias RideAlong.WebhookPublisher

  setup do
    lasso = Lasso.open()

    on_exit(fn ->
      Adept.set_trips([])
      Adept.set_vehicles([])
    end)

    webhooks = %{"http://127.0.0.1:#{lasso.port}/webhook" => "secret"}

    {:ok, _} =
      WebhookPublisher.start_link(
        start: true,
        secret: "global secret",
        name: __MODULE__,
        url_generator_mfa: {__MODULE__, :url_generator, []},
        webhooks: webhooks
      )

    {:ok, %{lasso: lasso}}
  end

  describe "sending notifications" do
    test "when receiving a trip notification message", %{lasso: lasso} do
      trip = AdeptFixtures.trip_fixture(%{})

      parent = self()
      ref = make_ref()
      {:ok, pid} = Agent.start_link(fn -> :not_set end)

      Lasso.expect(lasso, "POST", "/webhook", fn conn ->
        {:ok, body, conn} = Conn.read_body(conn)
        signature = Conn.get_req_header(conn, "x-signature-256")

        Agent.cast(pid, fn _ ->
          %{body: body, signature: signature}
        end)

        send(parent, ref)

        Plug.Conn.send_resp(conn, :created, "")
      end)

      PubSub.publish("notification:trip", {:trip_notification, trip})
      assert_receive ^ref
      assert %{body: body, signature: signature} = Agent.get(pid, & &1)

      assert %{
               "url" => "uri:1234",
               "status" => "ENQUEUED",
               "tripId" => 1234,
               "routeId" => 4567,
               "clientId" => 70_000,
               "notificationId" => _,
               "etaTime" => _,
               "promiseTime" => _
             } = Jason.decode!(body)

      expected_signature =
        :crypto.mac(:hmac, :sha256, "secret", body)
        |> Base.encode16()
        |> String.downcase()

      assert ["sha256=" <> ^expected_signature] =
               signature
    end
  end

  def url_generator(trip_id) do
    {:ok, "uri:#{trip_id}"}
  end
end
