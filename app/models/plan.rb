class Plan < ApplicationRecord
  PLANS = {
    smb: { id: 'price_99_smb', name: 'SMB ($99/mo)', amount: 99 },
    enterprise: { id: 'price_2k_ent', name: 'Enterprise ($2K/mo)', amount: 2000 }
  }.freeze
  
  def self.plans
    PLANS.values
  end
end
