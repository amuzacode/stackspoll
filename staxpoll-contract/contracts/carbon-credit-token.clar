;; title: carbon-credit-token
;; version: 1.0

(define-fungible-token carbon-credit)

(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u100))
(define-constant err-project-already-exists (err u101))
(define-constant err-project-not-found (err u102))
(define-constant err-invalid-offset-amount (err u103))
(define-constant err-insufficient-balance (err u104))

(define-map projects
  { project-id: (string-ascii 64) }
  {
    verified: bool,
    offset-amount: uint,
    project-owner: principal
  }
)

;; SIP-010 transfer function
(define-public (transfer (amount uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) err-not-authorized)
    (ft-transfer? carbon-credit amount sender recipient)
  )
)

;; Allow contract-based transfers
(define-public (transfer-from (amount uint) (sender principal) (recipient principal))
  (ft-transfer? carbon-credit amount sender recipient)
)

(define-public (create-project (project-id (string-ascii 64)) (offset-amount uint))
  (let ((project-exists (map-get? projects { project-id: project-id })))
    (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
    (asserts! (is-none project-exists) err-project-already-exists)
    (asserts! (> offset-amount u0) err-invalid-offset-amount)
    
    (map-set projects
      { project-id: project-id }
      {
        verified: false,
        offset-amount: offset-amount,
        project-owner: tx-sender
      }
    )
    (ok true)
  )
)

(define-public (verify-project (project-id (string-ascii 64)))
  (let ((project (map-get? projects { project-id: project-id })))
    (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
    (asserts! (is-some project) err-project-not-found)
    
    (map-set projects
      { project-id: project-id }
      (merge (unwrap-panic project) { verified: true })
    )
    (ok true)
  )
)

(define-public (mint-carbon-credits (project-id (string-ascii 64)))
  (let (
    (project (unwrap! (map-get? projects { project-id: project-id }) err-project-not-found))
    (offset-amount (get offset-amount project))
  )
    (asserts! (is-eq tx-sender (get project-owner project)) err-not-authorized)
    (asserts! (get verified project) err-not-authorized)
    
    (ft-mint? carbon-credit offset-amount (get project-owner project))
  )
)

(define-read-only (get-project-details (project-id (string-ascii 64)))
  (map-get? projects { project-id: project-id })
)

(define-read-only (get-balance (address principal))
  (ft-get-balance carbon-credit address)
)

;; Required by SIP-010
(define-read-only (get-name)
  (ok "Carbon Credit Token")
)

(define-read-only (get-symbol)
  (ok "CCT")
)

(define-read-only (get-decimals)
  (ok u6)
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply carbon-credit))
)