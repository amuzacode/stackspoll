;; Revenue Sharing & Transaction Fee Contract
;; Handles platform fees, revenue distribution, and token staking

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-AUTHORIZED (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-INSUFFICIENT-BALANCE (err u103))
(define-constant ERR-INVALID-PERCENTAGE (err u104))
(define-constant ERR-NO-STAKES (err u105))
(define-constant ERR-STAKING-PERIOD-NOT-ENDED (err u106))

;; Data Variables
(define-data-var platform-fee-percentage uint u250) ;; 2.5% (250 basis points)
(define-data-var environmental-share uint u4000) ;; 40% of fees
(define-data-var investor-share uint u3000) ;; 30% of fees
(define-data-var staker-share uint u3000) ;; 30% of fees
(define-data-var total-fees-collected uint u0)
(define-data-var total-staked uint u0)
(define-data-var reward-rate uint u500) ;; 5% annual reward rate (500 basis points)

;; Data Maps
(define-map user-stakes 
  principal 
  {
    amount: uint,
    stake-block: uint,
    last-reward-block: uint
  }
)

(define-map environmental-projects 
  principal 
  {
    allocation-percentage: uint,
    total-received: uint,
    active: bool
  }
)

(define-map investors 
  principal 
  {
    allocation-percentage: uint,
    total-received: uint,
    active: bool
  }
)

(define-map fee-distribution-history
  uint ;; block height
  {
    total-amount: uint,
    environmental-amount: uint,
    investor-amount: uint,
    staker-amount: uint,
    timestamp: uint
  }
)

;; Read-only functions
(define-read-only (get-platform-fee-percentage)
  (var-get platform-fee-percentage)
)

(define-read-only (get-revenue-shares)
  {
    environmental: (var-get environmental-share),
    investor: (var-get investor-share),
    staker: (var-get staker-share)
  }
)

(define-read-only (get-user-stake (user principal))
  (map-get? user-stakes user)
)

(define-read-only (get-total-staked)
  (var-get total-staked)
)

(define-read-only (get-total-fees-collected)
  (var-get total-fees-collected)
)

(define-read-only (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-percentage)) u10000)
)

(define-read-only (calculate-staking-rewards (user principal))
  (match (map-get? user-stakes user)
    stake-info
    (let
      (
        (blocks-staked (- stacks-block-height (get last-reward-block stake-info)))
        (stake-amount (get amount stake-info))
        (annual-blocks u52560) ;; Approximate blocks per year (assuming 10 min blocks)
        (reward-amount (/ (* (* stake-amount (var-get reward-rate)) blocks-staked) (* u10000 annual-blocks)))
      )
      reward-amount
    )
    u0
  )
)

(define-read-only (get-environmental-project (project principal))
  (map-get? environmental-projects project)
)

(define-read-only (get-investor (investor principal))
  (map-get? investors investor)
)

;; Private functions
(define-private (distribute-to-environmental-projects (amount uint))
  (let
    (
      (distribution-amount amount)
    )
    ;; In a real implementation, you would iterate through all active environmental projects
    ;; For simplicity, we'll just track the total amount to be distributed
    (var-set total-fees-collected (+ (var-get total-fees-collected) distribution-amount))
    (ok distribution-amount)
  )
)

(define-private (distribute-to-investors (amount uint))
  (let
    (
      (distribution-amount amount)
    )
    ;; In a real implementation, you would iterate through all active investors
    ;; For simplicity, we'll just track the total amount to be distributed
    (var-set total-fees-collected (+ (var-get total-fees-collected) distribution-amount))
    (ok distribution-amount)
  )
)

(define-private (distribute-to-stakers (amount uint))
  (let
    (
      (total-staked-amount (var-get total-staked))
    )
    (if (> total-staked-amount u0)
      (begin
        ;; Add to staker reward pool (simplified implementation)
        (var-set total-fees-collected (+ (var-get total-fees-collected) amount))
        (ok amount)
      )
      (ok u0)
    )
  )
)

;; Public functions

;; Process transaction with automatic fee deduction
(define-public (process-transaction (amount uint))
  (let
    (
      (fee-amount (calculate-platform-fee amount))
      (net-amount (- amount fee-amount))
      (env-amount (/ (* fee-amount (var-get environmental-share)) u10000))
      (investor-amount (/ (* fee-amount (var-get investor-share)) u10000))
      (staker-amount (/ (* fee-amount (var-get staker-share)) u10000))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    

    ;; Distribute fees (these now return proper ok/err responses)
    (unwrap! (distribute-to-environmental-projects env-amount) ERR-INVALID-AMOUNT)
    (unwrap! (distribute-to-investors investor-amount) ERR-INVALID-AMOUNT)
    (unwrap! (distribute-to-stakers staker-amount) ERR-INVALID-AMOUNT)
    
    ;; Record distribution history
    (map-set fee-distribution-history 
      stacks-block-height
      {
        total-amount: fee-amount,
        environmental-amount: env-amount,
        investor-amount: investor-amount,
        staker-amount: staker-amount,
        timestamp: stacks-block-height
      }
    )
    
    (var-set total-fees-collected (+ (var-get total-fees-collected) fee-amount))
    
    (ok {
      original-amount: amount,
      fee-amount: fee-amount,
      net-amount: net-amount,
      distributions: {
        environmental: env-amount,
        investor: investor-amount,
        staker: staker-amount
      }
    })
  )
)

;; Stake tokens
(define-public (stake-tokens (amount uint))
  (let
    (
      (current-stake (default-to 
        { amount: u0, stake-block: u0, last-reward-block: u0 }
        (map-get? user-stakes tx-sender)
      ))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Update user stake
    (map-set user-stakes tx-sender
      {
        amount: (+ (get amount current-stake) amount),
        stake-block: (if (is-eq (get amount current-stake) u0) stacks-block-height (get stake-block current-stake)),
        last-reward-block: stacks-block-height
      }
    )
    
    ;; Update total staked
    (var-set total-staked (+ (var-get total-staked) amount))
    
    (ok amount)
  )
)

;; Unstake tokens
(define-public (unstake-tokens (amount uint))
  (let
    (
      (current-stake (unwrap! (map-get? user-stakes tx-sender) ERR-NO-STAKES))
      (staked-amount (get amount current-stake))
    )
    (asserts! (>= staked-amount amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Calculate and distribute rewards before unstaking
    (let
      (
        (rewards (calculate-staking-rewards tx-sender))
        (new-stake-amount (- staked-amount amount))
      )
      
      ;; Update or remove stake
      (if (is-eq new-stake-amount u0)
        (map-delete user-stakes tx-sender)
        (map-set user-stakes tx-sender
          {
            amount: new-stake-amount,
            stake-block: (get stake-block current-stake),
            last-reward-block: stacks-block-height
          }
        )
      )
      
      ;; Update total staked
      (var-set total-staked (- (var-get total-staked) amount))
      
      (ok {
        unstaked-amount: amount,
        rewards-earned: rewards,
        remaining-stake: new-stake-amount
      })
    )
  )
)

;; Claim staking rewards
(define-public (claim-staking-rewards)
  (let
    (
      (current-stake (unwrap! (map-get? user-stakes tx-sender) ERR-NO-STAKES))
      (rewards (calculate-staking-rewards tx-sender))
    )
    (asserts! (> rewards u0) ERR-INVALID-AMOUNT)
    
    ;; Update last reward block
    (map-set user-stakes tx-sender
      (merge current-stake { last-reward-block: stacks-block-height })
    )
    
    (ok rewards)
  )
)

;; Admin functions

;; Update platform fee percentage (only owner)
(define-public (set-platform-fee-percentage (new-percentage uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= new-percentage u1000) ERR-INVALID-PERCENTAGE) ;; Max 10%
    (var-set platform-fee-percentage new-percentage)
    (ok new-percentage)
  )
)

;; Update revenue sharing percentages (only owner)
(define-public (set-revenue-shares (env-share uint) (inv-share uint) (stake-share uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (is-eq (+ env-share inv-share stake-share) u10000) ERR-INVALID-PERCENTAGE)
    (var-set environmental-share env-share)
    (var-set investor-share inv-share)
    (var-set staker-share stake-share)
    (ok true)
  )
)

;; Add environmental project (only owner)
(define-public (add-environmental-project (project principal) (allocation uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= allocation u10000) ERR-INVALID-PERCENTAGE)
    (map-set environmental-projects project
      {
        allocation-percentage: allocation,
        total-received: u0,
        active: true
      }
    )
    (ok true)
  )
)

;; Add investor (only owner)
(define-public (add-investor (investor principal) (allocation uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= allocation u10000) ERR-INVALID-PERCENTAGE)
    (map-set investors investor
      {
        allocation-percentage: allocation,
        total-received: u0,
        active: true
      }
    )
    (ok true)
  )
)

;; Update reward rate (only owner)
(define-public (set-reward-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= new-rate u2000) ERR-INVALID-PERCENTAGE) ;; Max 20% annual
    (var-set reward-rate new-rate)
    (ok new-rate)
  )
)

;; Emergency functions

;; Pause contract (only owner)
(define-data-var contract-paused bool false)

(define-public (toggle-contract-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set contract-paused (not (var-get contract-paused)))
    (ok (var-get contract-paused))
  )
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)
