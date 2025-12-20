class HomeController < ApplicationController
  def landing
    render layout: false, file: Rails.root.join('public', 'index.html')
  end
end
