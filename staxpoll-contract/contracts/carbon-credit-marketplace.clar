;; title: carbon-credit-marketplace
;; version: 1.0
;; depends-on: carbon-credit-token

;; Constants and Settings
(define-constant contract-owner tx-sender)
(define-constant listing-duration u432000) ;; 5 days in blocks
(define-constant min-price u1000000) ;; minimum listing price

;; Error codes
(define-constant err-not-authorized (err u200))
(define-constant err-invalid-price (err u201))
(define-constant err-listing-not-found (err u202))
(define-constant err-listing-expired (err u203))
(define-constant err-insufficient-balance (err u204))
(define-constant err-already-registered (err u205))

;; Data Maps
(define-map participants 
  principal
  {
    registered: bool,
    participant-type: (string-ascii 10), ;; "buyer" or "seller"
    reputation-score: uint
  }
)

(define-map listings
  uint
  {
    seller: principal,
    token-amount: uint,
    price-per-token: uint,
    expiry: uint,
    status: (string-ascii 10) ;; "active", "sold", "cancelled"
  }
)

(define-map escrow
  uint
  {
    buyer: principal,
    amount: uint,
    completed: bool
  }
)

;; Counter for listing IDs
(define-data-var listing-nonce uint u0)

;; Registration Functions
(define-public (register-participant (participant-type (string-ascii 10)))
  (let ((existing-registration (map-get? participants tx-sender)))
    (asserts! (is-none existing-registration) err-already-registered)
    (asserts! (or (is-eq participant-type "buyer") (is-eq participant-type "seller")) err-not-authorized)
    
    (map-set participants 
      tx-sender
      {
        registered: true,
        participant-type: participant-type,
        reputation-score: u100
      }
    )
    (ok true)
  )
)

;; Listing Functions
(define-public (create-listing (token-amount uint) (price-per-token uint))
  (let (
    (listing-id (+ (var-get listing-nonce) u1))
    (participant (unwrap! (map-get? participants tx-sender) err-not-authorized))
  )
    (asserts! (is-eq (get participant-type participant) "seller") err-not-authorized)
    (asserts! (>= price-per-token min-price) err-invalid-price)
    (asserts! (>= (contract-call? .carbon-credit-token get-balance tx-sender) token-amount) err-insufficient-balance)
    
    (try! (contract-call? .carbon-credit-token transfer token-amount tx-sender (as-contract tx-sender) (some 0x7472616e73666572)))
    
    (map-set listings 
      listing-id
      {
        seller: tx-sender,
        token-amount: token-amount,
        price-per-token: price-per-token,
        expiry: (+ block-height listing-duration),
        status: "active"
      }
    )
    
    (var-set listing-nonce listing-id)
    (ok listing-id)
  )
)

;; Purchase Functions
(define-public (purchase-listing (listing-id uint))
  (let (
    (listing (unwrap! (map-get? listings listing-id) err-listing-not-found))
    (buyer-info (unwrap! (map-get? participants tx-sender) err-not-authorized))
    (total-price (* (get price-per-token listing) (get token-amount listing)))
  )
    (asserts! (is-eq (get participant-type buyer-info) "buyer") err-not-authorized)
    (asserts! (is-eq (get status listing) "active") err-listing-not-found)
    (asserts! (< block-height (get expiry listing)) err-listing-expired)
    
    ;; Transfer payment to escrow
    (try! (stx-transfer? total-price tx-sender (as-contract tx-sender)))
    
    ;; Update escrow
    (map-set escrow
      listing-id
      {
        buyer: tx-sender,
        amount: total-price,
        completed: false
      }
    )
    
    ;; Update listing status
    (map-set listings
      listing-id
      (merge listing { status: "pending" })
    )
    (ok true)
  )
)

;; Escrow completion
(define-public (complete-transaction (listing-id uint))
  (let (
    (listing (unwrap! (map-get? listings listing-id) err-listing-not-found))
    (escrow-info (unwrap! (map-get? escrow listing-id) err-listing-not-found))
  )
    (asserts! (is-eq tx-sender (get seller listing)) err-not-authorized)
    
    ;; Transfer tokens to buyer
    (try! (as-contract (contract-call? .carbon-credit-token transfer 
      (get token-amount listing) 
      tx-sender 
      (get buyer escrow-info)
      (some 0x7472616e73666572)
    )))
    
    ;; Transfer payment to seller
    (try! (as-contract (stx-transfer? 
      (get amount escrow-info) 
      tx-sender 
      (get seller listing)
    )))
    
    ;; Update status
    (map-set listings listing-id (merge listing { status: "sold" }))
    (map-set escrow listing-id (merge escrow-info { completed: true }))
    
    (ok true)
  )
)

;; Getter Functions
(define-read-only (get-listing (listing-id uint))
  (map-get? listings listing-id)
)

(define-read-only (get-participant-info (address principal))
  (map-get? participants address)
)

(define-read-only (get-escrow-info (listing-id uint))
  (map-get? escrow listing-id)
)