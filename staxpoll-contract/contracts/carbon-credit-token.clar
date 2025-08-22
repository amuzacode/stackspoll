;; Carbon Credit Token Contract
;; A smart contract for tokenized carbon credit issuance with verification and minting capabilities

;; Define the fungible token for carbon credits (1 token = 1 ton CO2 offset)
(define-fungible-token carbon-credit)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-verifier (err u101))
(define-constant err-project-not-found (err u102))
(define-constant err-project-not-verified (err u103))
(define-constant err-project-already-exists (err u104))
(define-constant err-insufficient-balance (err u105))
(define-constant err-invalid-amount (err u106))
(define-constant err-project-already-verified (err u107))
(define-constant err-invalid-project-data (err u108))

;; Data Variables
(define-data-var total-credits-issued uint u0)
(define-data-var verification-fee uint u1000000) ;; 1 STX in microSTX

;; Data Maps
(define-map authorized-verifiers principal bool)
(define-map carbon-projects 
  { project-id: (string-ascii 64) }
  {
    owner: principal,
    project-type: (string-ascii 32), ;; "reforestation", "renewable-energy", "carbon-capture", etc.
    location: (string-ascii 64),
    estimated-offset: uint, ;; tons of CO2
    verification-status: (string-ascii 16), ;; "pending", "verified", "rejected"
    verifier: (optional principal),
    verification-date: (optional uint),
    credits-minted: uint,
    metadata-uri: (optional (string-ascii 256))
  }
)

(define-map project-credits 
  { project-id: (string-ascii 64), credit-batch: uint }
  {
    amount: uint,
    mint-date: uint,
    recipient: principal
  }
)

(define-map user-balances principal uint)

;; Authorization Functions
(define-public (add-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-verifiers verifier true))
  )
)

(define-public (remove-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete authorized-verifiers verifier))
  )
)

(define-read-only (is-authorized-verifier (verifier principal))
  (default-to false (map-get? authorized-verifiers verifier))
)

;; Project Registration Functions
(define-public (register-project 
  (project-id (string-ascii 64))
  (project-type (string-ascii 32))
  (location (string-ascii 64))
  (estimated-offset uint)
  (metadata-uri (optional (string-ascii 256)))
)
  (let 
    (
      (existing-project (map-get? carbon-projects { project-id: project-id }))
    )
    (asserts! (is-none existing-project) err-project-already-exists)
    (asserts! (> estimated-offset u0) err-invalid-project-data)
    (asserts! (> (len project-id) u0) err-invalid-project-data)
    
    (ok (map-set carbon-projects 
      { project-id: project-id }
      {
        owner: tx-sender,
        project-type: project-type,
        location: location,
        estimated-offset: estimated-offset,
        verification-status: "pending",
        verifier: none,
        verification-date: none,
        credits-minted: u0,
        metadata-uri: metadata-uri
      }
    ))
  )
)

;; Verification Functions
(define-public (verify-project 
  (project-id (string-ascii 64))
  (approved bool)
  (verified-offset uint)
)
  (let
    (
      (project (unwrap! (map-get? carbon-projects { project-id: project-id }) err-project-not-found))
    )
    (asserts! (is-authorized-verifier tx-sender) err-not-verifier)
    (asserts! (is-eq (get verification-status project) "pending") err-project-already-verified)
    
    (if approved
      (ok (map-set carbon-projects 
        { project-id: project-id }
        (merge project {
          verification-status: "verified",
          verifier: (some tx-sender),
          verification-date: (some block-height),
          estimated-offset: verified-offset
        })
      ))
      (ok (map-set carbon-projects 
        { project-id: project-id }
        (merge project {
          verification-status: "rejected",
          verifier: (some tx-sender),
          verification-date: (some block-height)
        })
      ))
    )
  )
)

;; Carbon Credit Minting Functions
(define-public (mint-carbon-credits 
  (project-id (string-ascii 64))
  (amount uint)
  (recipient principal)
)
  (let
    (
      (project (unwrap! (map-get? carbon-projects { project-id: project-id }) err-project-not-found))
      (current-minted (get credits-minted project))
      (max-mintable (get estimated-offset project))
    )
    (asserts! (is-eq tx-sender (get owner project)) err-owner-only)
    (asserts! (is-eq (get verification-status project) "verified") err-project-not-verified)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (<= (+ current-minted amount) max-mintable) err-invalid-amount)
    
    ;; Mint tokens
    (try! (ft-mint? carbon-credit amount recipient))
    
    ;; Update project data
    (map-set carbon-projects 
      { project-id: project-id }
      (merge project { credits-minted: (+ current-minted amount) })
    )
    
    ;; Record credit batch
    (map-set project-credits
      { project-id: project-id, credit-batch: (+ current-minted u1) }
      {
        amount: amount,
        mint-date: block-height,
        recipient: recipient
      }
    )
    
    ;; Update total issued
    (var-set total-credits-issued (+ (var-get total-credits-issued) amount))
    
    (ok amount)
  )
)

;; Token Transfer Functions
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq tx-sender sender) err-owner-only)
    (ft-transfer? carbon-credit amount sender recipient)
  )
)

;; Retirement/Burning Functions (for carbon offset usage)
(define-public (retire-credits (amount uint) (memo (string-ascii 128)))
  (let
    (
      (sender-balance (ft-get-balance carbon-credit tx-sender))
    )
    (asserts! (>= sender-balance amount) err-insufficient-balance)
    (asserts! (> amount u0) err-invalid-amount)
    
    ;; Burn the tokens to represent permanent retirement
    (try! (ft-burn? carbon-credit amount tx-sender))
    
    ;; Emit retirement event (would be logged in transaction)
    (ok { 
      retired-by: tx-sender,
      amount: amount,
      retirement-date: block-height,
      memo: memo
    })
  )
)

;; Read-only Functions
(define-read-only (get-project-info (project-id (string-ascii 64)))
  (map-get? carbon-projects { project-id: project-id })
)

(define-read-only (get-credit-batch (project-id (string-ascii 64)) (batch uint))
  (map-get? project-credits { project-id: project-id, credit-batch: batch })
)

(define-read-only (get-balance (account principal))
  (ft-get-balance carbon-credit account)
)

(define-read-only (get-total-supply)
  (ft-get-supply carbon-credit)
)

(define-read-only (get-total-credits-issued)
  (var-get total-credits-issued)
)

(define-read-only (get-token-name)
  (ok "Carbon Credit Token")
)

(define-read-only (get-token-symbol)
  (ok "CCT")
)

(define-read-only (get-decimals)
  (ok u0) ;; No decimals since 1 token = 1 ton CO2
)

(define-read-only (get-verification-fee)
  (var-get verification-fee)
)

;; Administrative Functions
(define-public (set-verification-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (var-set verification-fee new-fee))
  )
)

(define-public (update-project-metadata 
  (project-id (string-ascii 64))
  (new-metadata-uri (string-ascii 256))
)
  (let
    (
      (project (unwrap! (map-get? carbon-projects { project-id: project-id }) err-project-not-found))
    )
    (asserts! (is-eq tx-sender (get owner project)) err-owner-only)
    
    (ok (map-set carbon-projects 
      { project-id: project-id }
      (merge project { metadata-uri: (some new-metadata-uri) })
    ))
  )
)

;; Initialize contract with owner as first verifier
(map-set authorized-verifiers contract-owner true)