;; Rent Distributor Contract
;; Automatically distributes rental income to property token holders
;; Calculates proportional distributions and manages rent collection

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-invalid-amount (err u202))
(define-constant err-unauthorized (err u203))
(define-constant err-already-distributed (err u204))
(define-constant err-insufficient-funds (err u205))

;; Data Variables
(define-data-var contract-admin principal tx-sender)
(define-data-var next-distribution-id uint u1)
(define-data-var distribution-fee-rate uint u100) ;; 1% fee

;; Data Maps
;; Rent collection records
(define-map rent-collections
  { property-id: uint, collection-date: uint }
  {
    total-amount: uint,
    collection-type: (string-ascii 20), ;; monthly, quarterly, annual
    collected-by: principal,
    distribution-status: (string-ascii 20), ;; pending, distributed, failed
    expenses-deducted: uint,
    net-distributable: uint
  }
)

;; Distribution records
(define-map distributions
  { distribution-id: uint }
  {
    property-id: uint,
    total-amount: uint,
    total-recipients: uint,
    distribution-date: uint,
    status: (string-ascii 20), ;; completed, partial, failed
    expenses: uint,
    fees: uint
  }
)

;; Individual recipient distributions
(define-map recipient-distributions
  { distribution-id: uint, recipient: principal }
  {
    amount: uint,
    ownership-percentage: uint,
    distribution-date: uint,
    claimed: bool,
    claim-date: uint
  }
)

;; Property expense tracking
(define-map property-expenses
  { property-id: uint, expense-date: uint }
  {
    expense-type: (string-ascii 50),
    amount: uint,
    description: (string-ascii 200),
    submitted-by: principal,
    approved: bool,
    approved-by: (optional principal)
  }
)

;; Read-only functions
(define-read-only (get-rent-collection (property-id uint) (collection-date uint))
  (map-get? rent-collections { property-id: property-id, collection-date: collection-date })
)

(define-read-only (get-distribution (distribution-id uint))
  (map-get? distributions { distribution-id: distribution-id })
)

(define-read-only (get-recipient-distribution (distribution-id uint) (recipient principal))
  (map-get? recipient-distributions { distribution-id: distribution-id, recipient: recipient })
)

;; Public functions
;; Collect rent for a property
(define-public (collect-rent (property-id uint) (amount uint) (collection-type (string-ascii 20)) (expenses uint))
  (begin
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (<= expenses amount) err-invalid-amount)
    
    (let ((net-amount (- amount expenses)))
      
      (map-set rent-collections
        { property-id: property-id, collection-date: stacks-block-height }
        {
          total-amount: amount,
          collection-type: collection-type,
          collected-by: tx-sender,
          distribution-status: "pending",
          expenses-deducted: expenses,
          net-distributable: net-amount
        }
      )
      
      (ok true)
    )
  )
)

;; Distribute rent to token holders
(define-public (distribute-rent (property-id uint) (collection-date uint))
  (begin
    (let ((rent-data (unwrap! (get-rent-collection property-id collection-date) err-not-found))
          (distribution-id (var-get next-distribution-id))
          (distributable-amount (get net-distributable rent-data))
          (distribution-fee (/ (* distributable-amount (var-get distribution-fee-rate)) u10000))
          (net-distribution (- distributable-amount distribution-fee)))
      
      (asserts! (is-eq (get distribution-status rent-data) "pending") err-already-distributed)
      
      ;; Create distribution record
      (map-set distributions
        { distribution-id: distribution-id }
        {
          property-id: property-id,
          total-amount: net-distribution,
          total-recipients: u0,
          distribution-date: stacks-block-height,
          status: "completed",
          expenses: (get expenses-deducted rent-data),
          fees: distribution-fee
        }
      )
      
      ;; Update rent collection status
      (map-set rent-collections
        { property-id: property-id, collection-date: collection-date }
        (merge rent-data { distribution-status: "distributed" })
      )
      
      (var-set next-distribution-id (+ distribution-id u1))
      (ok distribution-id)
    )
  )
)

;; Claim distributed rent
(define-public (claim-rent-distribution (distribution-id uint))
  (begin
    (let ((recipient-data (unwrap! (get-recipient-distribution distribution-id tx-sender) err-not-found)))
      
      (asserts! (not (get claimed recipient-data)) err-already-distributed)
      
      ;; Transfer STX to recipient
      (try! (as-contract (stx-transfer? (get amount recipient-data) tx-sender tx-sender)))
      
      ;; Mark as claimed
      (map-set recipient-distributions
        { distribution-id: distribution-id, recipient: tx-sender }
        (merge recipient-data { 
          claimed: true,
          claim-date: stacks-block-height
        })
      )
      
      (ok (get amount recipient-data))
    )
  )
)

;; Admin functions
(define-public (update-distribution-fee (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) err-owner-only)
    (asserts! (<= new-rate u1000) err-invalid-amount) ;; Max 10%
    (var-set distribution-fee-rate new-rate)
    (ok new-rate)
  )
)

(define-public (update-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) err-owner-only)
    (var-set contract-admin new-admin)
    (ok true)
  )
)

