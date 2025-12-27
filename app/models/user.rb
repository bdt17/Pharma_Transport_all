class User < ApplicationRecord
  # FDA 21 CFR Part 11 Audit Trail (exclude password_digest for security)
  has_paper_trail meta: { tenant_id: :tenant_id },
                  versions: { class_name: "PaperTrail::Version" },
                  ignore: [:password_digest, :encrypted_password]

  has_secure_password validations: false  # Allow Devise encrypted_password to coexist

  belongs_to :organization, optional: true
  belongs_to :tenant, optional: true
  has_many :audit_logs
  has_many :electronic_signatures

  validates :email, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, if: -> { password_digest_changed? || new_record? && password_digest.present? }

  enum :role, {
    viewer: 'viewer',
    operator: 'operator',
    admin: 'admin',
    super_admin: 'super_admin'
  }, prefix: true

  scope :active, -> { where(active: true) }
  scope :for_tenant, ->(tenant) { where(tenant: tenant) }

  def admin?
    role_admin? || role_super_admin?
  end

  def can_manage_api_keys?
    role_admin? || role_super_admin?
  end

  def record_login!
    update_column(:last_login_at, Time.current)
  end
end
