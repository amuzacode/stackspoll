
;; title: carbon-credit-retirement
;; version:
;; summary:
;; description:

;; Carbon Credit Retirement Contract
;; This contract manages the issuance, transfer, and retirement of carbon credits

;; Define error codes
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ALREADY_RETIRED (err u101))
(define-constant ERR_INSUFFICIENT_BALANCE (err u102))
(define-constant ERR_CREDIT_NOT_FOUND (err u103))

;; Define data maps
;; Track credit ownership
(define-map credit-balances 
  { owner: principal, credit-id: uint } 
  { amount: uint })

;; Track credit metadata and status
(define-map credits 
  { credit-id: uint }
  { 
    issuer: principal,
    total-supply: uint,
    retired-amount: uint,
    metadata-url: (string-utf8 256),
    is-active: bool
  })

;; Track retired credits by user
(define-map retired-credits
  { owner: principal, credit-id: uint }
  { amount: uint, retirement-date: uint })

;; Variables
(define-data-var credit-id-nonce uint u0)
(define-data-var contract-owner principal tx-sender)

;; Read-only functions

;; Get the balance of a specific credit for a user
(define-read-only (get-balance (owner principal) (credit-id uint))
  (default-to u0
    (get amount
      (map-get? credit-balances { owner: owner, credit-id: credit-id }))))

;; Get credit information
(define-read-only (get-credit-info (credit-id uint))
  (map-get? credits { credit-id: credit-id }))

;; Get retired amount for a user
(define-read-only (get-retired-amount (owner principal) (credit-id uint))
  (default-to u0
    (get amount
      (map-get? retired-credits { owner: owner, credit-id: credit-id }))))

;; Check if a credit is active
(define-read-only (is-credit-active (credit-id uint))
  (default-to false
    (get is-active
      (map-get? credits { credit-id: credit-id }))))

;; Public functions

;; Issue new carbon credits
(define-public (issue-credits (amount uint) (metadata-url (string-utf8 256)))
  (let ((new-credit-id (+ (var-get credit-id-nonce) u1)))
    ;; Update the nonce
    (var-set credit-id-nonce new-credit-id)
    
    ;; Create the credit
    (map-set credits
      { credit-id: new-credit-id }
      {
        issuer: tx-sender,
        total-supply: amount,
        retired-amount: u0,
        metadata-url: metadata-url,
        is-active: true
      })
    
    ;; Assign initial balance to issuer
    (map-set credit-balances
      { owner: tx-sender, credit-id: new-credit-id }
      { amount: amount })
    
    ;; Return the new credit ID
    (ok new-credit-id)))

;; Transfer carbon credits
(define-public (transfer (recipient principal) (credit-id uint) (amount uint))
  (let ((sender-balance (get-balance tx-sender credit-id)))
    ;; Check if credit exists and is active
    (asserts! (is-credit-active credit-id) ERR_CREDIT_NOT_FOUND)
    
    ;; Check if sender has enough balance
    (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
    
    ;; Update sender balance
    (map-set credit-balances
      { owner: tx-sender, credit-id: credit-id }
      { amount: (- sender-balance amount) })
    
    ;; Update recipient balance
    (map-set credit-balances
      { owner: recipient, credit-id: credit-id }
      { amount: (+ (get-balance recipient credit-id) amount) })
    
    (ok true)))

;; Retire carbon credits
(define-public (retire-credits (credit-id uint) (amount uint))
  (let (
    (sender-balance (get-balance tx-sender credit-id))
    (credit-info (unwrap! (get-credit-info credit-id) ERR_CREDIT_NOT_FOUND))
    (current-block-height stacks-block-height)
  )
    ;; Check if credit exists and is active
    (asserts! (get is-active credit-info) ERR_CREDIT_NOT_FOUND)
    
    ;; Check if sender has enough balance
    (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
    
    ;; Update sender balance (remove the credits)
    (map-set credit-balances
      { owner: tx-sender, credit-id: credit-id }
      { amount: (- sender-balance amount) })
    
    ;; Update retired credits for this user
    (map-set retired-credits
      { owner: tx-sender, credit-id: credit-id }
      { 
        amount: (+ (get-retired-amount tx-sender credit-id) amount),
        retirement-date: current-block-height
      })
    
    ;; Update total retired amount in credit info
    (map-set credits
      { credit-id: credit-id }
      (merge credit-info { retired-amount: (+ (get retired-amount credit-info) amount) }))
    
    ;; Emit retirement event
    (print { event: "credit-retired", credit-id: credit-id, amount: amount, owner: tx-sender })
    
    (ok true)))

;; Deactivate a credit (only issuer can do this)
(define-public (deactivate-credit (credit-id uint))
  (let ((credit-info (unwrap! (get-credit-info credit-id) ERR_CREDIT_NOT_FOUND)))
    ;; Check if caller is the issuer
    (asserts! (is-eq (get issuer credit-info) tx-sender) ERR_NOT_AUTHORIZED)
    
    ;; Update credit to inactive
    (map-set credits
      { credit-id: credit-id }
      (merge credit-info { is-active: false }))
    
    (ok true)))

;; Contract owner functions

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)))

