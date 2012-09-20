# Net::Ws

A ruby websocket client built on top of ruby's Net::HTTP.

## Installation

Add this line to your application's Gemfile:

    gem 'net-ws'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install net-ws

## Usage

    ws = Net::WS.new("ws://localhost:9000")
    ws.open
    ws.ping
    puts ws.send_text("Hello, World!")

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
