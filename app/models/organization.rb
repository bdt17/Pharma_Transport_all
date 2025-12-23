

class Organization < ApplicationRecord
  has_many :users
  has_one :subscription

validates :name, presence: true
  
  def active_subscription?
    subscription&.status == 'active'
  end
end

class Subscription < ApplicationRecord
  # ... existing code ...
  belongs_to :organization
  enum status: { trial: 0, active: 1, canceled: 2 }
end


has_many :users
has_one :subscription

def active_subscription?
  subscription&.status == 'active'
end
