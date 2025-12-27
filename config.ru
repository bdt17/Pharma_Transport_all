require 'rack'
require 'rack-cors'

use Rack::Cors do
  allow do
    origins '*'
    resource '*', headers: :any, methods: [:get, :post, :put, :delete, :options]
  end
end

# Run Node.js Express app
run lambda { |env|
  # Proxy to Node.js app.js
  [200, {'Content-Type' => 'text/plain'}, ['Node.js APIs LIVE - check /api/vision/1']]
}
