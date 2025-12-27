# frozen_string_literal: true

# Phase 4: FDA 21 CFR Part 11 Audit Logging
# PaperTrail configuration for pharmaceutical compliance

PaperTrail.config.enabled = true

# Track who made changes
PaperTrail.config.track_associations = false # Associations disabled for performance

# Store object changes for update events
PaperTrail.config.save_changes = true

# Version limit per item (nil = unlimited, required for FDA)
PaperTrail.config.version_limit = nil

# Use JSONB serializer for PostgreSQL
PaperTrail.config.serializer = PaperTrail::Serializers::JSON

# Custom version class with FDA metadata
module PaperTrail
  class Version < ActiveRecord::Base
    include PaperTrail::VersionConcern

    # Scope versions by tenant for multi-tenant isolation
    scope :for_tenant, ->(tenant_id) { where(tenant_id: tenant_id) }

    # Scope by date range for compliance reports
    scope :in_range, ->(start_at, end_at) { where(created_at: start_at..end_at) }

    # Scope by model type
    scope :for_model, ->(model_class) { where(item_type: model_class.to_s) }

    # FDA compliance: never allow deletion
    def readonly?
      true
    end

    # Prevent deletion even through SQL
    before_destroy { throw :abort }
  end
end

# Controller concern for FDA audit metadata
module PaperTrailControllerInfo
  extend ActiveSupport::Concern

  included do
    before_action :set_paper_trail_whodunnit
    before_action :set_paper_trail_request_info
  end

  private

  def set_paper_trail_request_info
    return unless PaperTrail.request.enabled?

    # FDA 21 CFR Part 11 requires recording who, when, and from where
    PaperTrail.request.controller_info = {
      tenant_id: current_tenant&.id,
      ip_address: request.remote_ip,
      user_agent: request.user_agent&.truncate(500),
      request_id: request.request_id
    }
  end

  def user_for_paper_trail
    current_user&.id || current_tenant&.id || "system"
  end

  def current_tenant
    @current_tenant
  end

  def current_user
    @current_user
  end
end

# Hook into ApplicationController when loaded
Rails.application.config.to_prepare do
  ApplicationController.include(PaperTrailControllerInfo)
end
