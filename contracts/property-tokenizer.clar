;; Property Tokenizer Contract
;; Creates and manages fractional ownership tokens for real estate properties
;; Handles property registration, token minting, and ownership tracking

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-property-not-active (err u105))
(define-constant err-unauthorized (err u106))
(define-constant err-invalid-percentage (err u107))
(define-constant err-token-limit-exceeded (err u108))

;; Data Variables
(define-data-var contract-admin principal tx-sender)
(define-data-var next-property-id uint u1)
(define-data-var total-properties uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% (250 basis points)

;; Define fungible token for property shares
(define-fungible-token property-token)

;; Data Maps
;; Property registry with comprehensive property information
(define-map properties
  { property-id: uint }
  {
    owner: principal,
    property-address: (string-ascii 200),
    property-type: (string-ascii 50), ;; residential, commercial, industrial, etc.
    total-value: uint,
    total-tokens: uint,
    tokens-issued: uint,
    listing-price: uint, ;; price per token
    status: (string-ascii 20), ;; active, paused, sold
    created-at: uint,
    last-updated: uint,
    verification-status: (string-ascii 20), ;; pending, verified, rejected
    property-details: (string-ascii 500)
  }
)

;; Token ownership tracking per property
(define-map property-token-balances
  { property-id: uint, owner: principal }
  {
    token-balance: uint,
    ownership-percentage: uint, ;; in basis points (10000 = 100%)
    purchase-price: uint, ;; total amount paid for tokens
    purchase-date: uint
  }
)

;; Property token metadata
(define-map property-token-metadata
  { property-id: uint }
  {
    token-name: (string-ascii 50),
    token-symbol: (string-ascii 10),
    token-decimals: uint,
    token-uri: (optional (string-ascii 256))
  }
)

;; Investment history and transactions
(define-map investment-transactions
  { transaction-id: uint }
  {
    property-id: uint,
    investor: principal,
    transaction-type: (string-ascii 20), ;; purchase, sale, transfer
    token-amount: uint,
    price-per-token: uint,
    total-amount: uint,
    timestamp: uint,
    counterparty: (optional principal)
  }
)

(define-data-var next-transaction-id uint u1)

;; Property valuation history
(define-map property-valuations
  { property-id: uint, valuation-date: uint }
  {
    appraised-value: uint,
    appraiser: principal,
    valuation-method: (string-ascii 50),
    confidence-level: uint, ;; 1-100 scale
    notes: (string-ascii 200)
  }
)

;; Property voting and governance
(define-map property-proposals
  { proposal-id: uint }
  {
    property-id: uint,
    proposer: principal,
    proposal-type: (string-ascii 50), ;; renovation, sale, management-change
    description: (string-ascii 500),
    voting-start: uint,
    voting-end: uint,
    votes-for: uint,
    votes-against: uint,
    status: (string-ascii 20), ;; active, passed, rejected, executed
    execution-date: uint
  }
)

(define-data-var next-proposal-id uint u1)

;; Investor voting records
(define-map investor-votes
  { proposal-id: uint, voter: principal }
  {
    vote: bool, ;; true = for, false = against
    voting-power: uint, ;; based on token ownership
    vote-timestamp: uint
  }
)

;; Property performance metrics
(define-map property-metrics
  { property-id: uint }
  {
    annual-rent: uint,
    occupancy-rate: uint, ;; in basis points
    maintenance-costs: uint,
    property-taxes: uint,
    insurance-costs: uint,
    net-operating-income: uint,
    last-updated: uint
  }
)

;; Read-only functions

;; Get property information
(define-read-only (get-property (property-id uint))
  (map-get? properties { property-id: property-id })
)

;; Get property token balance for owner
(define-read-only (get-property-token-balance (property-id uint) (owner principal))
  (map-get? property-token-balances { property-id: property-id, owner: owner })
)

;; Get property token metadata
(define-read-only (get-property-token-metadata (property-id uint))
  (map-get? property-token-metadata { property-id: property-id })
)

;; Get investment transaction
(define-read-only (get-investment-transaction (transaction-id uint))
  (map-get? investment-transactions { transaction-id: transaction-id })
)

;; Get property valuation
(define-read-only (get-property-valuation (property-id uint) (valuation-date uint))
  (map-get? property-valuations { property-id: property-id, valuation-date: valuation-date })
)

;; Get property proposal
(define-read-only (get-property-proposal (proposal-id uint))
  (map-get? property-proposals { proposal-id: proposal-id })
)

;; Get investor vote
(define-read-only (get-investor-vote (proposal-id uint) (voter principal))
  (map-get? investor-votes { proposal-id: proposal-id, voter: voter })
)

;; Get property metrics
(define-read-only (get-property-metrics (property-id uint))
  (map-get? property-metrics { property-id: property-id })
)

;; Calculate ownership percentage
(define-read-only (calculate-ownership-percentage (property-id uint) (token-amount uint))
  (match (get-property property-id)
    property-data
    (let ((total-tokens (get total-tokens property-data)))
      (if (> total-tokens u0)
        (ok (/ (* token-amount u10000) total-tokens))
        (err u109)
      )
    )
    err-not-found
  )
)

;; Get total properties count
(define-read-only (get-total-properties)
  (var-get total-properties)
)

;; Check if property is active
(define-read-only (is-property-active (property-id uint))
  (match (get-property property-id)
    property-data (is-eq (get status property-data) "active")
    false
  )
)

;; Get platform fee rate
(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)

;; Calculate platform fee
(define-read-only (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-rate)) u10000)
)

;; Public functions

;; Register a new property for tokenization
(define-public (register-property (property-address (string-ascii 200)) (property-type (string-ascii 50))
                                 (total-value uint) (total-tokens uint) (listing-price uint)
                                 (property-details (string-ascii 500)))
  (begin
    (asserts! (> total-value u0) err-invalid-amount)
    (asserts! (> total-tokens u0) err-invalid-amount)
    (asserts! (> listing-price u0) err-invalid-amount)
    
    (let ((property-id (var-get next-property-id)))
      
      (map-set properties
        { property-id: property-id }
        {
          owner: tx-sender,
          property-address: property-address,
          property-type: property-type,
          total-value: total-value,
          total-tokens: total-tokens,
          tokens-issued: u0,
          listing-price: listing-price,
          status: "active",
          created-at: stacks-block-height,
          last-updated: stacks-block-height,
          verification-status: "pending",
          property-details: property-details
        }
      )
      
      ;; Set default token metadata
      (map-set property-token-metadata
        { property-id: property-id }
        {
          token-name: (concat "Property Token " (unwrap-panic (to-consensus-buff? property-id))),
          token-symbol: "PROP",
          token-decimals: u6,
          token-uri: none
        }
      )
      
      ;; Initialize property metrics
      (map-set property-metrics
        { property-id: property-id }
        {
          annual-rent: u0,
          occupancy-rate: u0,
          maintenance-costs: u0,
          property-taxes: u0,
          insurance-costs: u0,
          net-operating-income: u0,
          last-updated: stacks-block-height
        }
      )
      
      (var-set next-property-id (+ property-id u1))
      (var-set total-properties (+ (var-get total-properties) u1))
      (ok property-id)
    )
  )
)

;; Purchase property tokens
(define-public (purchase-property-tokens (property-id uint) (token-amount uint))
  (begin
    (asserts! (is-property-active property-id) err-property-not-active)
    (asserts! (> token-amount u0) err-invalid-amount)
    
    (let ((property-data (unwrap! (get-property property-id) err-not-found))
          (available-tokens (- (get total-tokens property-data) (get tokens-issued property-data)))
          (price-per-token (get listing-price property-data))
          (total-cost (* token-amount price-per-token))
          (platform-fee (calculate-platform-fee total-cost))
          (net-payment (- total-cost platform-fee))
          (ownership-pct (unwrap! (calculate-ownership-percentage property-id token-amount) err-invalid-percentage))
          (transaction-id (var-get next-transaction-id)))
      
      (asserts! (<= token-amount available-tokens) err-token-limit-exceeded)
      
      ;; Transfer payment to property owner
      (try! (stx-transfer? net-payment tx-sender (get owner property-data)))
      
      ;; Transfer platform fee to contract admin
      (try! (stx-transfer? platform-fee tx-sender (var-get contract-admin)))
      
      ;; Mint property tokens to buyer
      (try! (ft-mint? property-token token-amount tx-sender))
      
      ;; Update property token balance
      (let ((current-balance (default-to
                               { token-balance: u0, ownership-percentage: u0, purchase-price: u0, purchase-date: u0 }
                               (get-property-token-balance property-id tx-sender))))
        
        (map-set property-token-balances
          { property-id: property-id, owner: tx-sender }
          {
            token-balance: (+ (get token-balance current-balance) token-amount),
            ownership-percentage: (+ (get ownership-percentage current-balance) ownership-pct),
            purchase-price: (+ (get purchase-price current-balance) total-cost),
            purchase-date: stacks-block-height
          }
        )
      )
      
      ;; Update property tokens issued
      (map-set properties
        { property-id: property-id }
        (merge property-data { tokens-issued: (+ (get tokens-issued property-data) token-amount) })
      )
      
      ;; Record transaction
      (map-set investment-transactions
        { transaction-id: transaction-id }
        {
          property-id: property-id,
          investor: tx-sender,
          transaction-type: "purchase",
          token-amount: token-amount,
          price-per-token: price-per-token,
          total-amount: total-cost,
          timestamp: stacks-block-height,
          counterparty: (some (get owner property-data))
        }
      )
      
      (var-set next-transaction-id (+ transaction-id u1))
      (ok transaction-id)
    )
  )
)

;; Transfer property tokens between investors
(define-public (transfer-property-tokens (property-id uint) (token-amount uint) (recipient principal))
  (begin
    (asserts! (> token-amount u0) err-invalid-amount)
    
    (let ((sender-balance (unwrap! (get-property-token-balance property-id tx-sender) err-not-found))
          (transaction-id (var-get next-transaction-id))
          (ownership-pct (unwrap! (calculate-ownership-percentage property-id token-amount) err-invalid-percentage)))
      
      (asserts! (>= (get token-balance sender-balance) token-amount) err-insufficient-balance)
      
      ;; Transfer fungible tokens
      (try! (ft-transfer? property-token token-amount tx-sender recipient))
      
      ;; Update sender balance
      (map-set property-token-balances
        { property-id: property-id, owner: tx-sender }
        {
          token-balance: (- (get token-balance sender-balance) token-amount),
          ownership-percentage: (- (get ownership-percentage sender-balance) ownership-pct),
          purchase-price: (get purchase-price sender-balance),
          purchase-date: (get purchase-date sender-balance)
        }
      )
      
      ;; Update recipient balance
      (let ((recipient-balance (default-to
                                { token-balance: u0, ownership-percentage: u0, purchase-price: u0, purchase-date: u0 }
                                (get-property-token-balance property-id recipient))))
        
        (map-set property-token-balances
          { property-id: property-id, owner: recipient }
          {
            token-balance: (+ (get token-balance recipient-balance) token-amount),
            ownership-percentage: (+ (get ownership-percentage recipient-balance) ownership-pct),
            purchase-price: (get purchase-price recipient-balance),
            purchase-date: stacks-block-height
          }
        )
      )
      
      ;; Record transaction
      (map-set investment-transactions
        { transaction-id: transaction-id }
        {
          property-id: property-id,
          investor: tx-sender,
          transaction-type: "transfer",
          token-amount: token-amount,
          price-per-token: u0,
          total-amount: u0,
          timestamp: stacks-block-height,
          counterparty: (some recipient)
        }
      )
      
      (var-set next-transaction-id (+ transaction-id u1))
      (ok transaction-id)
    )
  )
)

;; Create property governance proposal
(define-public (create-property-proposal (property-id uint) (proposal-type (string-ascii 50))
                                        (description (string-ascii 500)) (voting-duration uint))
  (begin
    (asserts! (is-property-active property-id) err-property-not-active)
    
    ;; Check if proposer owns tokens in this property
    (let ((proposer-balance (unwrap! (get-property-token-balance property-id tx-sender) err-unauthorized))
          (proposal-id (var-get next-proposal-id))
          (voting-start stacks-block-height)
          (voting-end (+ stacks-block-height voting-duration)))
      
      (asserts! (> (get token-balance proposer-balance) u0) err-unauthorized)
      
      (map-set property-proposals
        { proposal-id: proposal-id }
        {
          property-id: property-id,
          proposer: tx-sender,
          proposal-type: proposal-type,
          description: description,
          voting-start: voting-start,
          voting-end: voting-end,
          votes-for: u0,
          votes-against: u0,
          status: "active",
          execution-date: u0
        }
      )
      
      (var-set next-proposal-id (+ proposal-id u1))
      (ok proposal-id)
    )
  )
)

;; Vote on property proposal
(define-public (vote-on-proposal (proposal-id uint) (vote bool))
  (begin
    (let ((proposal-data (unwrap! (get-property-proposal proposal-id) err-not-found))
          (property-id (get property-id proposal-data))
          (voter-balance (unwrap! (get-property-token-balance property-id tx-sender) err-unauthorized))
          (voting-power (get token-balance voter-balance)))
      
      (asserts! (> voting-power u0) err-unauthorized)
      (asserts! (is-eq (get status proposal-data) "active") err-invalid-amount)
      (asserts! (<= stacks-block-height (get voting-end proposal-data)) err-invalid-amount)
      (asserts! (is-none (get-investor-vote proposal-id tx-sender)) err-already-exists)
      
      ;; Record vote
      (map-set investor-votes
        { proposal-id: proposal-id, voter: tx-sender }
        {
          vote: vote,
          voting-power: voting-power,
          vote-timestamp: stacks-block-height
        }
      )
      
      ;; Update proposal vote counts
      (map-set property-proposals
        { proposal-id: proposal-id }
        (merge proposal-data {
          votes-for: (if vote (+ (get votes-for proposal-data) voting-power) (get votes-for proposal-data)),
          votes-against: (if vote (get votes-against proposal-data) (+ (get votes-against proposal-data) voting-power))
        })
      )
      
      (ok true)
    )
  )
)

;; Add property valuation
(define-public (add-property-valuation (property-id uint) (appraised-value uint)
                                      (valuation-method (string-ascii 50)) (confidence-level uint)
                                      (notes (string-ascii 200)))
  (begin
    (asserts! (is-property-active property-id) err-property-not-active)
    (asserts! (> appraised-value u0) err-invalid-amount)
    (asserts! (<= confidence-level u100) err-invalid-percentage)
    
    (map-set property-valuations
      { property-id: property-id, valuation-date: stacks-block-height }
      {
        appraised-value: appraised-value,
        appraiser: tx-sender,
        valuation-method: valuation-method,
        confidence-level: confidence-level,
        notes: notes
      }
    )
    
    (ok true)
  )
)

;; Update property metrics
(define-public (update-property-metrics (property-id uint) (annual-rent uint) (occupancy-rate uint)
                                       (maintenance-costs uint) (property-taxes uint)
                                       (insurance-costs uint))
  (begin
    (let ((property-data (unwrap! (get-property property-id) err-not-found))
          (noi (- annual-rent (+ maintenance-costs property-taxes insurance-costs))))
      
      ;; Only property owner can update metrics
      (asserts! (is-eq tx-sender (get owner property-data)) err-unauthorized)
      (asserts! (<= occupancy-rate u10000) err-invalid-percentage)
      
      (map-set property-metrics
        { property-id: property-id }
        {
          annual-rent: annual-rent,
          occupancy-rate: occupancy-rate,
          maintenance-costs: maintenance-costs,
          property-taxes: property-taxes,
          insurance-costs: insurance-costs,
          net-operating-income: noi,
          last-updated: stacks-block-height
        }
      )
      
      (ok true)
    )
  )
)

;; Admin functions

;; Verify property
(define-public (verify-property (property-id uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) err-owner-only)
    
    (let ((property-data (unwrap! (get-property property-id) err-not-found)))
      
      (map-set properties
        { property-id: property-id }
        (merge property-data { verification-status: "verified" })
      )
      
      (ok true)
    )
  )
)

;; Update property status
(define-public (update-property-status (property-id uint) (new-status (string-ascii 20)))
  (begin
    (let ((property-data (unwrap! (get-property property-id) err-not-found)))
      
      ;; Property owner or admin can update status
      (asserts! (or (is-eq tx-sender (get owner property-data))
                    (is-eq tx-sender (var-get contract-admin))) err-unauthorized)
      
      (map-set properties
        { property-id: property-id }
        (merge property-data { status: new-status, last-updated: stacks-block-height })
      )
      
      (ok true)
    )
  )
)

;; Update platform fee rate
(define-public (update-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) err-owner-only)
    (asserts! (<= new-rate u1000) err-invalid-percentage) ;; Max 10%
    (var-set platform-fee-rate new-rate)
    (ok new-rate)
  )
)

;; Update contract admin
(define-public (update-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) err-owner-only)
    (var-set contract-admin new-admin)
    (ok true)
  )
)

