require 'rack'

run Rack::Builder.new do
  use Rack::Static, urls: ['/'], index: 'index.html', root: 'public'
  
  map '/' do
    run lambda { |env|
      [200, {'Content-Type' => 'text/html'}, ['Pharma Transport Dashboard']]
    }
  end
end
