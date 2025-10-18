;; Property Manager Contract
;; Handles maintenance requests, property management tasks, and operational costs
;; Coordinates with service providers and tracks property performance

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u300))
(define-constant err-not-found (err u301))
(define-constant err-invalid-amount (err u302))
(define-constant err-unauthorized (err u303))
(define-constant err-request-closed (err u304))
(define-constant err-invalid-status (err u305))

;; Data Variables
(define-data-var contract-admin principal tx-sender)
(define-data-var next-request-id uint u1)
(define-data-var next-service-provider-id uint u1)

;; Data Maps
;; Maintenance requests
(define-map maintenance-requests
  { request-id: uint }
  {
    property-id: uint,
    requester: principal,
    request-type: (string-ascii 50), ;; plumbing, electrical, hvac, etc.
    description: (string-ascii 500),
    priority: uint, ;; 1=low, 2=medium, 3=high, 4=emergency
    estimated-cost: uint,
    actual-cost: uint,
    status: (string-ascii 20), ;; open, assigned, in-progress, completed, cancelled
    created-at: uint,
    assigned-to: (optional principal),
    completed-at: uint,
    completion-notes: (string-ascii 500)
  }
)

;; Service providers registry
(define-map service-providers
  { provider-id: uint }
  {
    provider-name: (string-ascii 100),
    contact-info: (string-ascii 200),
    specialties: (list 10 (string-ascii 50)),
    rating: uint, ;; 1-100 scale
    total-jobs: uint,
    completed-jobs: uint,
    average-cost: uint,
    active: bool,
    registered-at: uint
  }
)

;; Property operational costs
(define-map operational-costs
  { property-id: uint, cost-date: uint }
  {
    cost-type: (string-ascii 50),
    amount: uint,
    description: (string-ascii 200),
    category: (string-ascii 30), ;; maintenance, utilities, insurance, taxes
    service-provider: (optional uint),
    approved: bool,
    paid: bool
  }
)

;; Property performance metrics
(define-map property-performance
  { property-id: uint, period: uint }
  {
    rental-income: uint,
    operational-expenses: uint,
    maintenance-costs: uint,
    vacancy-days: uint,
    tenant-satisfaction: uint, ;; 1-100 scale
    net-operating-income: uint,
    cash-flow: uint
  }
)

;; Read-only functions
(define-read-only (get-maintenance-request (request-id uint))
  (map-get? maintenance-requests { request-id: request-id })
)

(define-read-only (get-service-provider (provider-id uint))
  (map-get? service-providers { provider-id: provider-id })
)

(define-read-only (get-operational-cost (property-id uint) (cost-date uint))
  (map-get? operational-costs { property-id: property-id, cost-date: cost-date })
)

(define-read-only (get-property-performance (property-id uint) (period uint))
  (map-get? property-performance { property-id: property-id, period: period })
)

;; Public functions
;; Submit maintenance request
(define-public (submit-maintenance-request (property-id uint) (request-type (string-ascii 50))
                                         (description (string-ascii 500)) (priority uint)
                                         (estimated-cost uint))
  (begin
    (asserts! (and (>= priority u1) (<= priority u4)) err-invalid-amount)
    (asserts! (> estimated-cost u0) err-invalid-amount)
    
    (let ((request-id (var-get next-request-id)))
      
      (map-set maintenance-requests
        { request-id: request-id }
        {
          property-id: property-id,
          requester: tx-sender,
          request-type: request-type,
          description: description,
          priority: priority,
          estimated-cost: estimated-cost,
          actual-cost: u0,
          status: "open",
          created-at: stacks-block-height,
          assigned-to: none,
          completed-at: u0,
          completion-notes: ""
        }
      )
      
      (var-set next-request-id (+ request-id u1))
      (ok request-id)
    )
  )
)

;; Assign maintenance request to service provider
(define-public (assign-maintenance-request (request-id uint) (provider-id uint))
  (begin
    (let ((request-data (unwrap! (get-maintenance-request request-id) err-not-found))
          (provider-data (unwrap! (get-service-provider provider-id) err-not-found)))
      
      (asserts! (is-eq (get status request-data) "open") err-invalid-status)
      (asserts! (get active provider-data) err-unauthorized)
      
      (map-set maintenance-requests
        { request-id: request-id }
        (merge request-data {
          status: "assigned",
          assigned-to: (some tx-sender)
        })
      )
      
      (ok true)
    )
  )
)

;; Complete maintenance request
(define-public (complete-maintenance-request (request-id uint) (actual-cost uint)
                                           (completion-notes (string-ascii 500)))
  (begin
    (let ((request-data (unwrap! (get-maintenance-request request-id) err-not-found)))
      
      (asserts! (is-eq (get status request-data) "assigned") err-invalid-status)
      (asserts! (is-eq (some tx-sender) (get assigned-to request-data)) err-unauthorized)
      
      (map-set maintenance-requests
        { request-id: request-id }
        (merge request-data {
          actual-cost: actual-cost,
          status: "completed",
          completed-at: stacks-block-height,
          completion-notes: completion-notes
        })
      )
      
      ;; Update service provider stats
      (update-provider-stats (unwrap-panic (get assigned-to request-data)) actual-cost)
      
      (ok true)
    )
  )
)

;; Register service provider
(define-public (register-service-provider (provider-name (string-ascii 100)) (contact-info (string-ascii 200))
                                         (specialties (list 10 (string-ascii 50))))
  (begin
    (let ((provider-id (var-get next-service-provider-id)))
      
      (map-set service-providers
        { provider-id: provider-id }
        {
          provider-name: provider-name,
          contact-info: contact-info,
          specialties: specialties,
          rating: u80, ;; Start with good rating
          total-jobs: u0,
          completed-jobs: u0,
          average-cost: u0,
          active: true,
          registered-at: stacks-block-height
        }
      )
      
      (var-set next-service-provider-id (+ provider-id u1))
      (ok provider-id)
    )
  )
)

;; Record operational cost
(define-public (record-operational-cost (property-id uint) (cost-type (string-ascii 50)) (amount uint)
                                       (description (string-ascii 200)) (category (string-ascii 30)))
  (begin
    (asserts! (> amount u0) err-invalid-amount)
    
    (map-set operational-costs
      { property-id: property-id, cost-date: stacks-block-height }
      {
        cost-type: cost-type,
        amount: amount,
        description: description,
        category: category,
        service-provider: none,
        approved: false,
        paid: false
      }
    )
    
    (ok true)
  )
)

;; Private helper functions
(define-private (update-provider-stats (provider principal) (job-cost uint))
  ;; Simplified provider stats update
  ;; In a real implementation, this would update the provider's performance metrics
  true
)

;; Admin functions
(define-public (update-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) err-owner-only)
    (var-set contract-admin new-admin)
    (ok true)
  )
)

