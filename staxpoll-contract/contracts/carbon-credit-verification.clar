
;; title: carbon-credit-verification
;; version:
;; summary:
;; description:

;; Carbon Credit Verification and Auditing Contract

;; Define data maps
(define-map projects 
  { project-id: uint }
  { 
    owner: principal,
    verified: bool,
    total-credits: uint,
    last-report-block: uint
  }
)

(define-map audit-logs
  { log-id: uint }
  {
    project-id: uint,
    action: (string-ascii 20),
    amount: uint,
    timestamp: uint
  }
)

;; Define data variables
(define-data-var next-project-id uint u1)
(define-data-var next-log-id uint u1)

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-already-verified (err u101))
(define-constant err-not-verified (err u102))

;; Project registration
(define-public (register-project)
  (let ((project-id (var-get next-project-id)))
    (map-insert projects { project-id: project-id }
      { 
        owner: tx-sender,
        verified: false,
        total-credits: u0,
        last-report-block: block-height
      }
    )
    (var-set next-project-id (+ project-id u1))
    (ok project-id)
  )
)

;; Project verification by contract owner
(define-public (verify-project (project-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (match (map-get? projects { project-id: project-id })
      project
        (begin
          (asserts! (not (get verified project)) err-already-verified)
          (map-set projects { project-id: project-id }
            (merge project { verified: true })
          )
          (log-audit project-id "verified" u0)
          (ok true)
        )
      (err u404)
    )
  )
)

;; Mint carbon credits (only for verified projects)
(define-public (mint-credits (project-id uint) (amount uint))
  (let ((project (unwrap! (map-get? projects { project-id: project-id }) (err u404))))
    (asserts! (is-eq (get owner project) tx-sender) err-unauthorized)
    (asserts! (get verified project) err-not-verified)
    (map-set projects { project-id: project-id }
      (merge project { total-credits: (+ (get total-credits project) amount) })
    )
    (log-audit project-id "minted" amount)
    (ok true)
  )
)

;; Submit project report
(define-public (submit-report (project-id uint) (report-hash (buff 32)))
  (let ((project (unwrap! (map-get? projects { project-id: project-id }) (err u404))))
    (asserts! (is-eq (get owner project) tx-sender) err-unauthorized)
    (map-set projects { project-id: project-id }
      (merge project { last-report-block: block-height })
    )
    (log-audit project-id "reported" u0)
    (print report-hash)
    (ok true)
  )
)

;; Internal function to log audit trail
(define-private (log-audit (project-id uint) (action (string-ascii 20)) (amount uint))
  (let ((log-id (var-get next-log-id)))
    (map-insert audit-logs { log-id: log-id }
      {
        project-id: project-id,
        action: action,
        amount: amount,
        timestamp: block-height
      }
    )
    (var-set next-log-id (+ log-id u1))
    log-id
  )
)

;; Getter for project details
(define-read-only (get-project (project-id uint))
  (map-get? projects { project-id: project-id })
)

;; Getter for audit log
(define-read-only (get-audit-log (log-id uint))
  (map-get? audit-logs { log-id: log-id })
)