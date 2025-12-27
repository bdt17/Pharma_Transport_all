Rails.application.routes.draw do
  # ═══════════════════════════════════════════════════════════════════════════
  # HEALTH CHECKS - Kubernetes probes (no auth, before everything)
  # ═══════════════════════════════════════════════════════════════════════════
  get '/health/live', to: 'health#live'
  get '/health/ready', to: 'health#ready'
  get '/health/detailed', to: 'health#detailed'

  # ═══════════════════════════════════════════════════════════════════════════
  # STRIPE - Webhooks & Checkout (Production-Ready)
  # ═══════════════════════════════════════════════════════════════════════════
  namespace :stripe do
    # Webhook endpoint - receives all Stripe events
    # IMPORTANT: Configure this URL in Stripe Dashboard → Webhooks
    # URL: https://pharmatransport.io/stripe/webhooks
    post 'webhooks', to: 'webhooks#create'

    # Checkout sessions for subscription management
    post 'checkout_sessions', to: 'checkout_sessions#create'
    get 'checkout_sessions/success', to: 'checkout_sessions#success'
    get 'checkout_sessions/cancel', to: 'checkout_sessions#cancel'

    # Billing portal for self-service subscription management
    post 'checkout_sessions/portal', to: 'checkout_sessions#portal'
  end

  # Billing dashboard
  get 'billing', to: 'billing#index'
  get 'billing/plans', to: 'billing#plans'
  post 'billing/subscribe', to: 'billing#subscribe'

  # API ROUTES FIRST - Before React SPA catch-all
  post '/api/forecast/:vehicle_id', to: 'sensors#forecast'
  post '/api/tamper/:vehicle_id', to: 'sensors#tamper'
  get '/api/vision', to: 'sensors#vision'

  # Phase 11.5 Partner API - RESTful /api/v1 endpoints
  namespace :api do
    namespace :v1 do
      # Tenant (current tenant based on API key)
      get 'tenant', to: 'tenants#show'
      patch 'tenant', to: 'tenants#update'
      get 'tenant/stats', to: 'tenants#stats'

      # API Keys management
      resources :api_keys, only: [:index, :show, :create, :update, :destroy] do
        post :rotate, on: :member
      end

      # Core resources
      resources :shipments do
        get :temperature_events, on: :member
        get :geofence_events, on: :member
        get :alerts, on: :member
      end

      resources :temperature_events, only: [:index, :show, :create] do
        post :bulk, on: :collection, action: :bulk_create
      end

      resources :geofence_events, only: [:index, :show, :create]

      resources :alerts, only: [:index, :show, :create] do
        post :acknowledge, on: :member
        post :resolve, on: :member
        get :summary, on: :collection
      end

      # Audit logs (read-only with verification)
      resources :audit_logs, only: [:index, :show] do
        get :verify, on: :collection
        get :for_resource, on: :collection
      end

      # Status/health endpoints (public)
      get 'status', to: 'status#index'
      get 'status/health', to: 'status#health'
      get 'status/metrics', to: 'status#metrics'
      get 'status/ready', to: 'status#ready'
      get 'status/live', to: 'status#live'
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ADMIN ROUTES - Compliance Dashboard
  # ═══════════════════════════════════════════════════════════════════════════
  namespace :admin do
    # Compliance Dashboard
    get 'compliance', to: 'compliance#index', as: :compliance
    get 'compliance/export', to: 'compliance#export', as: :compliance_export
    get 'compliance/verify', to: 'compliance#verify', as: :compliance_verify
    get 'compliance/report', to: 'compliance#report', as: :compliance_report
    get 'compliance/search', to: 'compliance#search', as: :compliance_search

    # Analytics Dashboard - Executive Metrics
    get 'analytics', to: 'analytics#index', as: :analytics
    get 'analytics/mrr', to: 'analytics#mrr', as: :mrr_analytics
    get 'analytics/churn', to: 'analytics#churn', as: :churn_analytics
    get 'analytics/tenants', to: 'analytics#tenants', as: :tenants_analytics
    get 'analytics/export', to: 'analytics#export', as: :export_analytics
    post 'analytics/sync', to: 'analytics#sync', as: :sync_analytics
  end

  # React SPA routes AFTER APIs
  root 'dashboard#index'
  get 'dashboard', to: 'dashboard#index'
  get 'dashboard/shipments', to: 'dashboard#shipments'
  get 'dashboard/audit_trail', to: 'dashboard#audit_trail'
  get 'dashboard/subscription_required', to: 'dashboard#subscription_required'
  get 'pfizer', to: 'partners#pfizer'
  resources :sensors
  resources :partners

  get '/api/gps/:id', to: 'sensors#gps'           # Phase 14 GPS
  get '/api/subscribe', to: 'sensors#subscribe'  # Phase 14 Stripe
  get '/api/jetson', to: 'sensors#jetson'        # Phase 14 Vision

  get '/api/compliance/audit', to: 'compliance#audit'
  post '/api/compliance/sign', to: 'compliance#sign'
  get '/api/compliance/versions/:item_type/:item_id', to: 'compliance#versions'
end
