class Subscription < ApplicationRecord
  belongs_to :organization
  enum status: { trial: 0, active: 1, canceled: 2 }
end


belongs_to :organization
enum status: { trial: 0, active: 1, canceled: 2 }
