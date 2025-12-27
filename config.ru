require 'rack'
run Rack::Static.new('public', index: 'index.html')
