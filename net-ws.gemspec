# -*- encoding: utf-8 -*-
require File.expand_path('../lib/net/ws/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Eric Wollesen"]
  gem.email         = ["ericw@xmtp.net"]
  gem.description   = %q{A websocket client built on top of Net::HTTP.}
  gem.summary       = %q{A websocket client built on top of Net::HTTP.}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "net-ws"
  gem.require_paths = ["lib"]
  gem.version       = Net::Ws::VERSION

  gem.add_development_dependency("rake")
  gem.add_development_dependency("pry")
end
