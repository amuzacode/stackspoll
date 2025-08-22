;; Carbon Credit Retirement Contract
;; This contract manages the permanent retirement of carbon credits for offsetting claims

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_CREDITS (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_CREDIT_NOT_FOUND (err u103))
(define-constant ERR_ALREADY_RETIRED (err u104))
(define-constant ERR_INVALID_CREDIT_ID (err u105))
(define-constant ERR_RETIREMENT_NOT_FOUND (err u106))
(define-constant ERR_CONTRACT_PAUSED (err u107))
(define-constant ERR_INVALID_BENEFICIARY (err u108))
(define-constant ERR_BULK_RETIREMENT_FAILED (err u109))

;; Data Variables
(define-data-var next-credit-id uint u1)
(define-data-var next-retirement-id uint u1)
(define-data-var total-credits-issued uint u0)
(define-data-var total-credits-retired uint u0)
(define-data-var contract-paused bool false)

;; Carbon Credit Structure
(define-map carbon-credits
  uint  ;; credit-id
  {
    project-id: uint,
    owner: principal,
    vintage-year: uint,
    amount: uint,
    project-type: (string-ascii 50),
    project-location: (string-ascii 100),
    certification-standard: (string-ascii 50),
    issued-date: uint,
    is-retired: bool,
    retirement-id: (optional uint)
  }
)

;; User Credit Balances (aggregated view)
(define-map user-balances
  principal
  {
    total-active: uint,
    total-retired: uint
  }
)

;; Project Credit Balances
(define-map project-balances
  uint  ;; project-id
  {
    total-issued: uint,
    total-retired: uint,
    total-active: uint
  }
)

;; Retirement Records
(define-map retirement-records
  uint  ;; retirement-id
  {
    credit-id: uint,
    retiree: principal,
    beneficiary: (optional principal),
    retirement-reason: (string-ascii 200),
    retirement-date: uint,
    amount: uint,
    project-id: uint,
    vintage-year: uint,
    certification-hash: (buff 32),
    retirement-certificate: (string-ascii 100)
  }
)

;; Retirement Certificates (for verification)
(define-map retirement-certificates
  (buff 32)  ;; certificate-hash
  {
    retirement-id: uint,
    issued-to: principal,
    verification-status: bool,
    issue-date: uint
  }
)

;; Beneficiary Retirement Records (track offsets on behalf of others)
(define-map beneficiary-retirements
  {beneficiary: principal, retiree: principal}
  {
    total-amount: uint,
    retirement-count: uint,
    last-retirement: uint
  }
)

;; Retirement Statistics by Project Type
(define-map retirement-by-type
  (string-ascii 50)  ;; project-type
  {
    total-retired: uint,
    retirement-count: uint
  }
)

;; Administrative Functions

;; Pause/unpause contract
(define-public (set-contract-paused (paused bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-paused paused)
    (ok true)
  )
)

;; Credit Issuance Functions (simplified for retirement focus)

;; Issue new carbon credits
(define-public (issue-credits
  (project-id uint)
  (recipient principal)
  (amount uint)
  (vintage-year uint)
  (project-type (string-ascii 50))
  (project-location (string-ascii 100))
  (certification-standard (string-ascii 50))
)
  (let
    (
      (credit-id (var-get next-credit-id))
      (current-balance (default-to {total-active: u0, total-retired: u0} (map-get? user-balances recipient)))
      (project-balance (default-to {total-issued: u0, total-retired: u0, total-active: u0} (map-get? project-balances project-id)))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (not (var-get contract-paused)) ERR_CONTRACT_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Create credit record
    (map-set carbon-credits credit-id {
      project-id: project-id,
      owner: recipient,
      vintage-year: vintage-year,
      amount: amount,
      project-type: project-type,
      project-location: project-location,
      certification-standard: certification-standard,
      issued-date: stacks-block-height,
      is-retired: false,
      retirement-id: none
    })
    
    ;; Update user balance
    (map-set user-balances recipient {
      total-active: (+ (get total-active current-balance) amount),
      total-retired: (get total-retired current-balance)
    })
    
    ;; Update project balance
    (map-set project-balances project-id {
      total-issued: (+ (get total-issued project-balance) amount),
      total-retired: (get total-retired project-balance),
      total-active: (+ (get total-active project-balance) amount)
    })
    
    ;; Update global counters
    (var-set next-credit-id (+ credit-id u1))
    (var-set total-credits-issued (+ (var-get total-credits-issued) amount))
    
    (ok credit-id)
  )
)

;; Generate human-readable certificate ID
(define-private (generate-certificate-id (retirement-id uint))
  (if (< retirement-id u10)
    "RET-000"
    (if (< retirement-id u100) 
      "RET-00"
      (if (< retirement-id u1000)
        "RET-0" 
        "RET-")))
)

;; Core Retirement Functions

;; Retire carbon credits (main retirement function)
(define-public (retire-credits
  (credit-id uint)
  (retirement-reason (string-ascii 200))
  (beneficiary (optional principal))
)
  (let
    (
      (credit (unwrap! (map-get? carbon-credits credit-id) ERR_CREDIT_NOT_FOUND))
      (retirement-id (var-get next-retirement-id))
      (cert-hash (generate-certificate-hash credit-id retirement-id))
      (retirement-cert (generate-certificate-id retirement-id))
      (user-balance (unwrap! (map-get? user-balances (get owner credit)) ERR_CREDIT_NOT_FOUND))
      (project-balance (unwrap! (map-get? project-balances (get project-id credit)) ERR_CREDIT_NOT_FOUND))
    )
    (asserts! (not (var-get contract-paused)) ERR_CONTRACT_PAUSED)
    (asserts! (is-eq tx-sender (get owner credit)) ERR_UNAUTHORIZED)
    (asserts! (not (get is-retired credit)) ERR_ALREADY_RETIRED)
    
    ;; Create retirement record
    (map-set retirement-records retirement-id {
      credit-id: credit-id,
      retiree: tx-sender,
      beneficiary: beneficiary,
      retirement-reason: retirement-reason,
      retirement-date: stacks-block-height,
      amount: (get amount credit),
      project-id: (get project-id credit),
      vintage-year: (get vintage-year credit),
      certification-hash: cert-hash,
      retirement-certificate: retirement-cert
    })
    
    ;; Mark credit as retired (PERMANENT - cannot be undone)
    (map-set carbon-credits credit-id (merge credit {
      is-retired: true,
      retirement-id: (some retirement-id)
    }))
    
    ;; Generate retirement certificate
    (map-set retirement-certificates cert-hash {
      retirement-id: retirement-id,
      issued-to: tx-sender,
      verification-status: true,
      issue-date: stacks-block-height
    })
    
    ;; Update user balance
    (map-set user-balances tx-sender {
      total-active: (- (get total-active user-balance) (get amount credit)),
      total-retired: (+ (get total-retired user-balance) (get amount credit))
    })
    
    ;; Update project balance
    (map-set project-balances (get project-id credit) {
      total-issued: (get total-issued project-balance),
      total-retired: (+ (get total-retired project-balance) (get amount credit)),
      total-active: (- (get total-active project-balance) (get amount credit))
    })
    
    ;; Update retirement statistics by project type
    (unwrap! (update-retirement-stats (get project-type credit) (get amount credit)) ERR_RETIREMENT_NOT_FOUND)
    
    ;; Track beneficiary retirements if applicable
    (match beneficiary
      beneficiary-addr (unwrap! (update-beneficiary-retirement beneficiary-addr tx-sender (get amount credit)) ERR_RETIREMENT_NOT_FOUND)
      true
    )
    
    ;; Update global counters
    (var-set next-retirement-id (+ retirement-id u1))
    (var-set total-credits-retired (+ (var-get total-credits-retired) (get amount credit)))
    
    (ok retirement-id)
  )
)


;; Retire credits on behalf of another entity (corporate offsetting)
(define-public (retire-for-beneficiary
  (credit-id uint)
  (beneficiary principal)
  (retirement-reason (string-ascii 200))
)
  (begin
    (asserts! (not (is-eq beneficiary tx-sender)) ERR_INVALID_BENEFICIARY)
    (retire-credits credit-id retirement-reason (some beneficiary))
  )
)

;; Internal Helper Functions

;; Update retirement statistics by project type
(define-private (update-retirement-stats (project-type (string-ascii 50)) (amount uint))
  (let
    (
      (current-stats (default-to {total-retired: u0, retirement-count: u0} (map-get? retirement-by-type project-type)))
    )
    (map-set retirement-by-type project-type {
      total-retired: (+ (get total-retired current-stats) amount),
      retirement-count: (+ (get retirement-count current-stats) u1)
    })
    (ok true)
  )
)

;; Update beneficiary retirement tracking
(define-private (update-beneficiary-retirement (beneficiary principal) (retiree principal) (amount uint))
  (let
    (
      (current-record (default-to {total-amount: u0, retirement-count: u0, last-retirement: u0} 
                      (map-get? beneficiary-retirements {beneficiary: beneficiary, retiree: retiree})))
    )
    (map-set beneficiary-retirements {beneficiary: beneficiary, retiree: retiree} {
      total-amount: (+ (get total-amount current-record) amount),
      retirement-count: (+ (get retirement-count current-record) u1),
      last-retirement: stacks-block-height
    })
    (ok true)
  )
)

;; Generate certificate hash for verification
(define-private (generate-certificate-hash (credit-id uint) (retirement-id uint))
  (sha256 (concat (unwrap-panic (to-consensus-buff? credit-id)) (unwrap-panic (to-consensus-buff? retirement-id))))
)

;; Read-only Functions

;; Get credit information
(define-read-only (get-credit (credit-id uint))
  (map-get? carbon-credits credit-id)
)

;; Check if credit is retired
(define-read-only (is-credit-retired (credit-id uint))
  (match (map-get? carbon-credits credit-id)
    credit (get is-retired credit)
    false
  )
)

;; Get retirement record
(define-read-only (get-retirement-record (retirement-id uint))
  (map-get? retirement-records retirement-id)
)

;; Get user balance
(define-read-only (get-user-balance (user principal))
  (default-to {total-active: u0, total-retired: u0} (map-get? user-balances user))
)

;; Get project balance
(define-read-only (get-project-balance (project-id uint))
  (default-to {total-issued: u0, total-retired: u0, total-active: u0} (map-get? project-balances project-id))
)

;; Verify retirement certificate
(define-read-only (verify-retirement-certificate (cert-hash (buff 32)))
  (map-get? retirement-certificates cert-hash)
)

;; Get retirement statistics by project type
(define-read-only (get-retirement-stats-by-type (project-type (string-ascii 50)))
  (default-to {total-retired: u0, retirement-count: u0} (map-get? retirement-by-type project-type))
)

;; Get beneficiary retirement record
(define-read-only (get-beneficiary-retirements (beneficiary principal) (retiree principal))
  (default-to {total-amount: u0, retirement-count: u0, last-retirement: u0} 
             (map-get? beneficiary-retirements {beneficiary: beneficiary, retiree: retiree}))
)

;; Get global retirement statistics
(define-read-only (get-global-stats)
  {
    total-credits-issued: (var-get total-credits-issued),
    total-credits-retired: (var-get total-credits-retired),
    total-credits-active: (- (var-get total-credits-issued) (var-get total-credits-retired)),
    retirement-rate: (if (> (var-get total-credits-issued) u0)
                      (/ (* (var-get total-credits-retired) u100) (var-get total-credits-issued))
                      u0),
    next-credit-id: (var-get next-credit-id),
    next-retirement-id: (var-get next-retirement-id)
  }
)

;; Check if user can retire specific credit
(define-read-only (can-retire-credit (credit-id uint) (user principal))
  (match (map-get? carbon-credits credit-id)
    credit (and (is-eq (get owner credit) user) (not (get is-retired credit)))
    false
  )
)

;; Get retirement confirmation
(define-read-only (get-retirement-confirmation (credit-id uint))
  (match (map-get? carbon-credits credit-id)
    credit (if (get is-retired credit)
            (match (get retirement-id credit)
              retirement-id (map-get? retirement-records retirement-id)
              none)
            none)
    none
  )
)

;; Contract status and information
(define-read-only (get-contract-info)
  {
    contract-paused: (var-get contract-paused),
    owner: CONTRACT_OWNER,
    total-retirements: (- (var-get next-retirement-id) u1)
  }
)