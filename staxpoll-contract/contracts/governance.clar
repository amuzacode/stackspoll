;; Carbon Credit Platform Governance Contract
;; Allows carbon credit token holders to vote on platform governance decisions

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u101))
(define-constant ERR-PROPOSAL-NOT-ACTIVE (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-INSUFFICIENT-TOKENS (err u104))
(define-constant ERR-VOTING-PERIOD-ENDED (err u105))
(define-constant ERR-QUORUM-NOT-MET (err u106))
(define-constant ERR-PROPOSAL-NOT-PASSED (err u107))
(define-constant ERR-INVALID-PROPOSAL-TYPE (err u108))
(define-constant ERR-PROPOSAL-ALREADY-EXECUTED (err u109))

;; Data Variables
(define-data-var proposal-counter uint u0)
(define-data-var min-proposal-tokens uint u1000000) ;; 1 CCT (with 6 decimals)
(define-data-var voting-period uint u144) ;; Voting period in blocks (~24 hours)
(define-data-var quorum-threshold uint u20) ;; 20% quorum requirement
(define-data-var carbon-credit-token principal .carbon-credit-token)

;; Proposal Types
(define-constant PROPOSAL-TYPE-FEE-CHANGE u1)
(define-constant PROPOSAL-TYPE-VALIDATION-METHOD u2)
(define-constant PROPOSAL-TYPE-PROJECT-INCLUSION u3)
(define-constant PROPOSAL-TYPE-PARAMETER-CHANGE u4)

;; Proposal Status
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-PASSED u2)
(define-constant STATUS-REJECTED u3)
(define-constant STATUS-EXECUTED u4)

;; Token balances map
(define-map token-balances principal uint)

;; Data Maps
(define-map proposals
  uint
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposal-type: uint,
    target-contract: (optional principal),
    function-name: (optional (string-ascii 50)),
    parameters: (list 5 uint),
    votes-for: uint,
    votes-against: uint,
    total-votes: uint,
    start-block: uint,
    end-block: uint,
    status: uint,
    executed: bool
  }
)

(define-map votes
  {proposal-id: uint, voter: principal}
  {
    vote: bool, ;; true for yes, false for no
    tokens: uint,
    stacks-block-height: uint
  }
)

(define-map voter-participation
  principal
  {
    proposals-voted: uint,
    total-tokens-voted: uint
  }
)

;; Fee structure map for governance
(define-map platform-fees
  (string-ascii 50)
  uint
)

;; Validation methods map
(define-map validation-methods
  uint
  {
    name: (string-ascii 100),
    active: bool,
    parameters: (list 3 uint)
  }
)

;; Environmental projects map
(define-map environmental-projects
  uint
  {
    name: (string-ascii 100),
    description: (string-ascii 300),
    approved: bool,
    carbon-credits: uint
  }
)

;; Initialize default values
(map-set platform-fees "trading-fee" u250) ;; 2.5%
(map-set platform-fees "validation-fee" u100) ;; 1%
(map-set platform-fees "listing-fee" u50) ;; 0.5%

;; Read-only functions
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-voter-participation (voter principal))
  (default-to 
    {proposals-voted: u0, total-tokens-voted: u0}
    (map-get? voter-participation voter)
  )
)

(define-read-only (get-platform-fee (fee-type (string-ascii 50)))
  (default-to u0 (map-get? platform-fees fee-type))
)

(define-read-only (get-validation-method (method-id uint))
  (map-get? validation-methods method-id)
)

(define-read-only (get-environmental-project (project-id uint))
  (map-get? environmental-projects project-id)
)

(define-read-only (get-governance-parameters)
  {
    min-proposal-tokens: (var-get min-proposal-tokens),
    voting-period: (var-get voting-period),
    quorum-threshold: (var-get quorum-threshold),
    total-proposals: (var-get proposal-counter)
  }
)


(define-read-only (is-proposal-active (proposal-id uint))
  (match (get-proposal proposal-id)
    proposal (and 
      (is-eq (get status proposal) STATUS-ACTIVE)
      (<= stacks-block-height (get end-block proposal))
    )
    false
  )
)


;; Public functions


;; ;; Function to get token balance
(define-read-only (get-token-balance (user principal))
  (default-to u0 (map-get? token-balances user))
)

;; Function to set token balance (for testing/initialization)
(define-public (set-token-balance (user principal) (amount uint))
  (begin
    (map-set token-balances user amount)
    (ok true)
  )
)
;; Create a new governance proposal
(define-public (create-proposal 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (proposal-type uint)
  (target-contract (optional principal))
  (function-name (optional (string-ascii 50)))
  (parameters (list 5 uint)))
  (let (
    (proposer-tokens (get-token-balance tx-sender))
    (proposal-id (+ (var-get proposal-counter) u1))
    (start-block stacks-block-height)
    (end-block (+ stacks-block-height (var-get voting-period)))
  )
    (asserts! (>= proposer-tokens (var-get min-proposal-tokens)) ERR-INSUFFICIENT-TOKENS)
    (asserts! (<= proposal-type u4) ERR-INVALID-PROPOSAL-TYPE)
    (asserts! (> proposal-type u0) ERR-INVALID-PROPOSAL-TYPE)
    
    (map-set proposals proposal-id {
      proposer: tx-sender,
      title: title,
      description: description,
      proposal-type: proposal-type,
      target-contract: target-contract,
      function-name: function-name,
      parameters: parameters,
      votes-for: u0,
      votes-against: u0,
      total-votes: u0,
      start-block: start-block,
      end-block: end-block,
      status: STATUS-ACTIVE,
      executed: false
    })
    
    (var-set proposal-counter proposal-id)
    (ok proposal-id)
  )
)
;; Vote on a proposal
(define-public (vote (proposal-id uint) (support bool))
  (let (
    (proposal (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (voter-tokens (get-token-balance tx-sender))
    (existing-vote (get-vote proposal-id tx-sender))
  )
    (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
    (asserts! (> voter-tokens u0) ERR-INSUFFICIENT-TOKENS)
    (asserts! (is-proposal-active proposal-id) ERR-PROPOSAL-NOT-ACTIVE)
    
    ;; Record the vote
    (map-set votes 
      {proposal-id: proposal-id, voter: tx-sender}
      {
        vote: support,
        tokens: voter-tokens,
        stacks-block-height: stacks-block-height
      }
    )
    
    ;; Update proposal vote counts
    (map-set proposals proposal-id
      (merge proposal {
        votes-for: (if support 
          (+ (get votes-for proposal) voter-tokens)
          (get votes-for proposal)
        ),
        votes-against: (if support
          (get votes-against proposal)
          (+ (get votes-against proposal) voter-tokens)
        ),
        total-votes: (+ (get total-votes proposal) voter-tokens)
      })
    )
    
    ;; Update voter participation
    (let ((participation (get-voter-participation tx-sender)))
      (map-set voter-participation tx-sender {
        proposals-voted: (+ (get proposals-voted participation) u1),
        total-tokens-voted: (+ (get total-tokens-voted participation) voter-tokens)
      })
    )
    
    (ok true)
  )
)

;; Finalize a proposal after voting period ends
(define-public (finalize-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    (asserts! (is-eq (get status proposal) STATUS-ACTIVE) ERR-PROPOSAL-NOT-ACTIVE)
    (asserts! (> stacks-block-height (get end-block proposal)) ERR-VOTING-PERIOD-ENDED)
    
    (let (
      (total-votes (get total-votes proposal))
      (votes-for (get votes-for proposal))
      (votes-against (get votes-against proposal))
      ;; Determine if proposal passes (you may need to adjust this condition)
      (passed (> votes-for votes-against))
    )
      (map-set proposals proposal-id
        (merge proposal {
          status: (if passed STATUS-PASSED STATUS-REJECTED)
        })
      )
      
      (ok passed)
    )
  )
)
;; Execute a passed proposal (fixed version)
(define-public (execute-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (prop-type (get proposal-type proposal))
  )
    (asserts! (is-eq (get status proposal) STATUS-PASSED) ERR-PROPOSAL-NOT-PASSED)
    (asserts! (not (get executed proposal)) ERR-PROPOSAL-NOT-PASSED)
    
    ;; Execute based on proposal type using nested if statements
    (let (
      (execution-result 
        (if (is-eq prop-type PROPOSAL-TYPE-FEE-CHANGE)
            (execute-fee-change proposal)
        (if (is-eq prop-type PROPOSAL-TYPE-VALIDATION-METHOD)
            (execute-validation-method-change proposal)  
        (if (is-eq prop-type PROPOSAL-TYPE-PROJECT-INCLUSION)
            (execute-project-inclusion proposal)
        (if (is-eq prop-type PROPOSAL-TYPE-PARAMETER-CHANGE)
            (execute-parameter-change proposal)
            ERR-INVALID-PROPOSAL-TYPE
        ))))
      )
    )
      ;; Handle execution result and mark as executed
      (match execution-result
        success (begin
          ;; Mark as executed and return success
          (map-set proposals proposal-id 
            (merge proposal { executed: true }))
          (ok true)
        )
        error (err error)  ;; Return the unwrapped error
      )
    )
  )
)

;; Execute fee change proposal
(define-private (execute-fee-change (proposal {proposer: principal, title: (string-ascii 100), description: (string-ascii 500), proposal-type: uint, target-contract: (optional principal), function-name: (optional (string-ascii 50)), parameters: (list 5 uint), votes-for: uint, votes-against: uint, total-votes: uint, start-block: uint, end-block: uint, status: uint, executed: bool}))
  (let (
    (params (get parameters proposal))
    (fee-type-id (unwrap-panic (element-at params u0)))
    (new-fee (unwrap-panic (element-at params u1)))
  )
    ;; Map fee type ID to string
    (let (
      (fee-type (if (is-eq fee-type-id u1) "trading-fee"
                (if (is-eq fee-type-id u2) "validation-fee"
                "listing-fee")))
    )
      (map-set platform-fees fee-type new-fee)
      (ok true)
    )
  )
)

;; Execute validation method change
(define-private (execute-validation-method-change (proposal {proposer: principal, title: (string-ascii 100), description: (string-ascii 500), proposal-type: uint, target-contract: (optional principal), function-name: (optional (string-ascii 50)), parameters: (list 5 uint), votes-for: uint, votes-against: uint, total-votes: uint, start-block: uint, end-block: uint, status: uint, executed: bool}))
  (let (
    (params (get parameters proposal))
    (method-id (unwrap-panic (element-at params u0)))
    (active (is-eq (unwrap-panic (element-at params u1)) u1))
  )
    (match (get-validation-method method-id)
      existing-method (begin
        (map-set validation-methods method-id
          (merge existing-method {active: active})
        )
        (ok true)
      )
      (ok false)
    )
  )
)

;; Execute project inclusion
(define-private (execute-project-inclusion (proposal {proposer: principal, title: (string-ascii 100), description: (string-ascii 500), proposal-type: uint, target-contract: (optional principal), function-name: (optional (string-ascii 50)), parameters: (list 5 uint), votes-for: uint, votes-against: uint, total-votes: uint, start-block: uint, end-block: uint, status: uint, executed: bool}))
  (let (
    (params (get parameters proposal))
    (project-id (unwrap-panic (element-at params u0)))
    (approved (is-eq (unwrap-panic (element-at params u1)) u1))
  )
    (match (get-environmental-project project-id)
      existing-project (begin
        (map-set environmental-projects project-id
          (merge existing-project {approved: approved})
        )
        (ok true)
      )
      (ok false)
    )
  )
)

;; Execute parameter change
(define-private (execute-parameter-change (proposal {proposer: principal, title: (string-ascii 100), description: (string-ascii 500), proposal-type: uint, target-contract: (optional principal), function-name: (optional (string-ascii 50)), parameters: (list 5 uint), votes-for: uint, votes-against: uint, total-votes: uint, start-block: uint, end-block: uint, status: uint, executed: bool}))
  (let (
    (params (get parameters proposal))
    (param-type (unwrap-panic (element-at params u0)))
    (new-value (unwrap-panic (element-at params u1)))
  )
    (if (is-eq param-type u1)
      (begin (var-set min-proposal-tokens new-value) (ok true))
      (if (is-eq param-type u2)
        (begin (var-set voting-period new-value) (ok true))
        (if (is-eq param-type u3)
          (begin (var-set quorum-threshold new-value) (ok true))
          (ok false)
        )
      )
    )
  )
)

;; Admin functions (only contract owner)
(define-public (set-carbon-credit-token (new-token principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set carbon-credit-token new-token)
    (ok true)
  )
)

(define-public (add-validation-method 
  (method-id uint)
  (name (string-ascii 100))
  (parameters (list 3 uint))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set validation-methods method-id {
      name: name,
      active: true,
      parameters: parameters
    })
    (ok true)
  )
)

(define-public (add-environmental-project
  (project-id uint)
  (name (string-ascii 100))
  (description (string-ascii 300))
  (carbon-credits uint)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set environmental-projects project-id {
      name: name,
      description: description,
      approved: false,
      carbon-credits: carbon-credits
    })
    (ok true)
  )
)

;; Emergency functions
(define-public (emergency-pause-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set proposals proposal-id
      (merge proposal {status: STATUS-REJECTED})
    )
    (ok true)
  )
)

;; Integration functions with carbon credit token
(define-public (propose-project-verification (project-id (string-ascii 64)))
  (let (
    (proposal-id (+ (var-get proposal-counter) u1))
    (start-block stacks-block-height)
    (end-block (+ stacks-block-height (var-get voting-period)))
  )
    (asserts! (>= (get-token-balance tx-sender) (var-get min-proposal-tokens)) ERR-INSUFFICIENT-TOKENS)
    
    (map-set proposals proposal-id {
      proposer: tx-sender,
      title: "Project Verification Proposal",
      description: project-id,
      proposal-type: PROPOSAL-TYPE-PROJECT-INCLUSION,
      target-contract: (some (var-get carbon-credit-token)),
      function-name: (some "verify-project"),
      parameters: (list u1 u0 u0 u0 u0), ;; approve project
      votes-for: u0,
      votes-against: u0,
      total-votes: u0,
      start-block: start-block,
      end-block: end-block,
      status: STATUS-ACTIVE,
      executed: false
    })
    
    (var-set proposal-counter proposal-id)
    (ok proposal-id)
  )
)

(define-public (initialize-token-contract (token-contract principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set carbon-credit-token token-contract)
    (ok true)
  )
)

(define-read-only (get-token-contract)
  (var-get carbon-credit-token)
)

(define-read-only (is-token-contract-set)
  (not (is-eq (var-get carbon-credit-token) .carbon-credit-token))
)
