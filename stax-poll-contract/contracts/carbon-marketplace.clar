;; Carbon Credit Marketplace
;; A marketplace for buying and selling tokenized carbon credits

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-registered (err u101))
(define-constant err-already-registered (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-listing-not-found (err u104))
(define-constant err-escrow-not-found (err u105))
(define-constant err-unauthorized (err u106))
(define-constant err-auction-ended (err u107))
(define-constant err-bid-too-low (err u108))

;; Define buyer and seller types
(define-data-var next-buyer-id uint u1)
(define-data-var next-seller-id uint u1)
(define-data-var next-listing-id uint u1)
(define-data-var next-escrow-id uint u1)

;; Data maps for buyers and sellers
(define-map buyers uint {
  address: principal,
  business-type: (string-utf8 50),
  verified: bool
})

(define-map sellers uint {
  address: principal,
  project-name: (string-utf8 100),
  project-type: (string-utf8 50),
  verified: bool
})

;; Map to track addresses to their IDs
(define-map address-to-buyer principal uint)
(define-map address-to-seller principal uint)

;; Listings for carbon credits
(define-map listings uint {
  seller-id: uint,
  token-amount: uint,
  price-per-token: uint,
  is-auction: bool,
  auction-end-height: uint,
  highest-bidder: (optional uint),
  highest-bid: uint
})

;; Escrow system
(define-map escrows uint {
  buyer-id: uint,
  seller-id: uint,
  listing-id: uint,
  amount: uint,
  price: uint,
  completed: bool
})

;; Token balances
(define-map token-balances principal uint)

;; Register a buyer
(define-public (register-buyer (business-type (string-utf8 50)))
  (let ((buyer-id (var-get next-buyer-id)))
    (asserts! (is-none (map-get? address-to-buyer tx-sender)) err-already-registered)
    
    (map-set buyers buyer-id {
      address: tx-sender,
      business-type: business-type,
      verified: false
    })
    
    (map-set address-to-buyer tx-sender buyer-id)
    (var-set next-buyer-id (+ buyer-id u1))
    (ok buyer-id)
  )
)

;; Register a seller
(define-public (register-seller (project-name (string-utf8 100)) (project-type (string-utf8 50)))
  (let ((seller-id (var-get next-seller-id)))
    (asserts! (is-none (map-get? address-to-seller tx-sender)) err-already-registered)
    
    (map-set sellers seller-id {
      address: tx-sender,
      project-name: project-name,
      project-type: project-type,
      verified: false
    })
    
    (map-set address-to-seller tx-sender seller-id)
    (var-set next-seller-id (+ seller-id u1))
    (ok seller-id)
  )
)

;; Verify a buyer or seller (admin only)
(define-public (verify-buyer (buyer-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (match (map-get? buyers buyer-id)
      buyer (ok (map-set buyers buyer-id (merge buyer { verified: true })))
      err-not-registered
    )
  )
)

(define-public (verify-seller (seller-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (match (map-get? sellers seller-id)
      seller (ok (map-set sellers seller-id (merge seller { verified: true })))
      err-not-registered
    )
  )
)

;; Mint tokens (simplified - in a real contract, this would be more complex)
(define-public (mint-tokens (amount uint))
  (begin
    (asserts! (is-some (map-get? address-to-seller tx-sender)) err-not-registered)
    (let ((current-balance (default-to u0 (map-get? token-balances tx-sender))))
      (map-set token-balances tx-sender (+ current-balance amount))
      (ok amount)
    )
  )
)

;; Create a fixed price listing
(define-public (create-fixed-price-listing (token-amount uint) (price-per-token uint))
  (let (
    (seller-id (unwrap! (map-get? address-to-seller tx-sender) err-not-registered))
    (listing-id (var-get next-listing-id))
    (seller-balance (default-to u0 (map-get? token-balances tx-sender)))
  )
    (asserts! (>= seller-balance token-amount) err-insufficient-balance)
    
    ;; Reduce seller's balance
    (map-set token-balances tx-sender (- seller-balance token-amount))
    
    ;; Create listing
    (map-set listings listing-id {
      seller-id: seller-id,
      token-amount: token-amount,
      price-per-token: price-per-token,
      is-auction: false,
      auction-end-height: u0,
      highest-bidder: none,
      highest-bid: u0
    })
    
    (var-set next-listing-id (+ listing-id u1))
    (ok listing-id)
  )
)

;; Create an auction listing
(define-public (create-auction-listing (token-amount uint) (min-price-per-token uint) (blocks-duration uint))
  (let (
    (seller-id (unwrap! (map-get? address-to-seller tx-sender) err-not-registered))
    (listing-id (var-get next-listing-id))
    (seller-balance (default-to u0 (map-get? token-balances tx-sender)))
    (auction-end (+ stacks-block-height blocks-duration))
  )
    (asserts! (>= seller-balance token-amount) err-insufficient-balance)
    
    ;; Reduce seller's balance
    (map-set token-balances tx-sender (- seller-balance token-amount))
    
    ;; Create listing
    (map-set listings listing-id {
      seller-id: seller-id,
      token-amount: token-amount,
      price-per-token: min-price-per-token,
      is-auction: true,
      auction-end-height: auction-end,
      highest-bidder: none,
      highest-bid: u0
    })
    
    (var-set next-listing-id (+ listing-id u1))
    (ok listing-id)
  )
)

;; Buy tokens at fixed price
(define-public (buy-fixed-price-listing (listing-id uint) (amount uint))
  (let (
    (buyer-id (unwrap! (map-get? address-to-buyer tx-sender) err-not-registered))
    (listing (unwrap! (map-get? listings listing-id) err-listing-not-found))
    (total-price (* amount (get price-per-token listing)))
    (escrow-id (var-get next-escrow-id))
  )
    ;; Validate the purchase
    (asserts! (not (get is-auction listing)) err-unauthorized)
    (asserts! (<= amount (get token-amount listing)) err-insufficient-balance)
    
    ;; Create escrow
    (map-set escrows escrow-id {
      buyer-id: buyer-id,
      seller-id: (get seller-id listing),
      listing-id: listing-id,
      amount: amount,
      price: total-price,
      completed: false
    })
    
    ;; Update listing
    (map-set listings listing-id 
      (merge listing { token-amount: (- (get token-amount listing) amount) })
    )
    
    (var-set next-escrow-id (+ escrow-id u1))
    (ok escrow-id)
  )
)

;; Place a bid in an auction
(define-public (place-bid (listing-id uint) (bid-per-token uint))
  (let (
    (buyer-id (unwrap! (map-get? address-to-buyer tx-sender) err-not-registered))
    (listing (unwrap! (map-get? listings listing-id) err-listing-not-found))
    (total-bid (* bid-per-token (get token-amount listing)))
  )
    ;; Validate the bid
    (asserts! (get is-auction listing) err-unauthorized)
    (asserts! (< stacks-block-height (get auction-end-height listing)) err-auction-ended)
    (asserts! (> bid-per-token (get price-per-token listing)) err-bid-too-low)
    
    ;; Update listing with new bid
    (map-set listings listing-id 
      (merge listing { 
        highest-bidder: (some buyer-id),
        highest-bid: total-bid,
        price-per-token: bid-per-token
      })
    )
    
    (ok total-bid)
  )
)

;; Finalize auction
(define-public (finalize-auction (listing-id uint))
  (let (
    (listing (unwrap! (map-get? listings listing-id) err-listing-not-found))
    (escrow-id (var-get next-escrow-id))
  )
    ;; Validate auction can be finalized
    (asserts! (get is-auction listing) err-unauthorized)
    (asserts! (>= stacks-block-height (get auction-end-height listing)) err-unauthorized)
    
    ;; Check if there was a winning bid
    (match (get highest-bidder listing)
      winner-id
        ;; Create escrow for the winning bid
        (begin
          (map-set escrows escrow-id {
            buyer-id: winner-id,
            seller-id: (get seller-id listing),
            listing-id: listing-id,
            amount: (get token-amount listing),
            price: (get highest-bid listing),
            completed: false
          })
          (var-set next-escrow-id (+ escrow-id u1))
          (ok escrow-id)
        )
      ;; No bids, return tokens to seller
      (let (
        (seller (unwrap! (map-get? sellers (get seller-id listing)) err-not-registered))
        (seller-balance (default-to u0 (map-get? token-balances (get address seller))))
      )
        (map-set token-balances 
          (get address seller) 
          (+ seller-balance (get token-amount listing))
        )
        (ok u0)
      )
    )
  )
)

;; Complete escrow transaction (payment confirmation)
(define-public (complete-escrow (escrow-id uint))
  (let (
    (escrow (unwrap! (map-get? escrows escrow-id) err-escrow-not-found))
    (buyer (unwrap! (map-get? buyers (get buyer-id escrow)) err-not-registered))
    (seller (unwrap! (map-get? sellers (get seller-id escrow)) err-not-registered))
    (buyer-balance (default-to u0 (map-get? token-balances (get address buyer))))
  )
    ;; Only contract owner can complete escrow (in a real system, this would be triggered by payment confirmation)
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (get completed escrow)) err-unauthorized)
    
    ;; Transfer tokens to buyer
    (map-set token-balances 
      (get address buyer) 
      (+ buyer-balance (get amount escrow))
    )
    
    ;; Mark escrow as completed
    (map-set escrows escrow-id
      (merge escrow { completed: true })
    )
    
    (ok true)
  )
)

;; Get buyer details
(define-read-only (get-buyer (buyer-id uint))
  (map-get? buyers buyer-id)
)

;; Get seller details
(define-read-only (get-seller (seller-id uint))
  (map-get? sellers seller-id)
)

;; Get listing details
(define-read-only (get-listing (listing-id uint))
  (map-get? listings listing-id)
)

;; Get escrow details
(define-read-only (get-escrow (escrow-id uint))
  (map-get? escrows escrow-id)
)

;; Get token balance
(define-read-only (get-balance (address principal))
  (default-to u0 (map-get? token-balances address))
)