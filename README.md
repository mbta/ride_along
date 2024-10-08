# RideAlong

A small pair of apps to enable paratransit riders to see the location and ETA of their app.

## Development

To start your Phoenix server:

  * Run `brew install git-lfs` to ensure the model can be downloaded
  * Run `git lfs checkout` to download the model
  * Run `mise install` to install the correct versions of Elixir/Erlang/NodeJS
  * Run `npm i --prefix assets` to install NodeJS packages
  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4001`](https://localhost:4001) from your browser.

## Testing

  * `mix checks.dev`
  * `mix checks.test`
