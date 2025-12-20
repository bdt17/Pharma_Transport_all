class Driver < ApplicationRecord
  validates :name, :phone, presence: true
end
