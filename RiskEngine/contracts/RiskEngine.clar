;; On-Chain Risk Assessment for Lending Protocols
;; A comprehensive smart contract that evaluates and monitors lending risks in real-time.
;; This system assesses borrower creditworthiness, collateral health, market volatility,
;; and protocol-wide risk metrics to ensure safe lending operations and prevent liquidation cascades.

;; constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-BORROWER (err u101))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u102))
(define-constant ERR-RISK-TOO-HIGH (err u103))
(define-constant ERR-MARKET-VOLATILITY (err u104))

;; Risk thresholds and parameters
(define-constant MAX-LTV-RATIO u80) ;; 80% max loan-to-value
(define-constant LIQUIDATION-THRESHOLD u85) ;; 85% liquidation threshold
(define-constant HIGH-RISK-THRESHOLD u75) ;; 75% risk score triggers alerts
(define-constant VOLATILITY-LIMIT u30) ;; 30% max daily volatility
(define-constant MIN-COLLATERAL-DIVERSITY u3) ;; Minimum 3 collateral types

;; data maps and vars
(define-data-var total-borrowed uint u0)
(define-data-var total-collateral-value uint u0)
(define-data-var protocol-risk-score uint u0)
(define-data-var emergency-mode bool false)

(define-map borrower-profiles
  principal
  {
    credit-score: uint,
    total-borrowed: uint,
    collateral-value: uint,
    liquidation-risk: uint,
    last-assessment: uint,
    default-history: uint
  })

(define-map collateral-assets
  (string-ascii 10) ;; asset symbol
  {
    price: uint,
    volatility: uint,
    liquidity-score: uint,
    risk-weight: uint,
    last-update: uint
  })

(define-map lending-positions
  { borrower: principal, asset: (string-ascii 10) }
  {
    borrowed-amount: uint,
    collateral-amount: uint,
    ltv-ratio: uint,
    health-factor: uint,
    created-at: uint
  })

;; private functions
(define-private (calculate-health-factor (collateral-value uint) (borrowed-amount uint))
  (if (is-eq borrowed-amount u0)
    u999 ;; Perfect health if no debt
    (/ (* collateral-value u100) (* borrowed-amount LIQUIDATION-THRESHOLD))))

(define-private (assess-volatility-risk (asset (string-ascii 10)))
  (match (map-get? collateral-assets asset)
    asset-data (if (> (get volatility asset-data) VOLATILITY-LIMIT) u100 u0)
    u50)) ;; Default moderate risk for unknown assets

(define-private (calculate-credit-score (borrower principal))
  (match (map-get? borrower-profiles borrower)
    profile 
      (let ((base-score u100)
            (default-penalty (* (get default-history profile) u10))
            (utilization-factor (if (> (get total-borrowed profile) u0)
                                  (/ (* (get total-borrowed profile) u100) 
                                     (get collateral-value profile))
                                  u0)))
        (if (> (+ default-penalty utilization-factor) base-score)
          u0
          (- base-score (+ default-penalty utilization-factor))))
    u50)) ;; Default score for new borrowers

(define-private (validate-collateral-diversity (borrower principal))
  ;; Simplified check - in production would analyze actual collateral composition
  true)

;; public functions
(define-public (register-borrower (borrower principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set borrower-profiles borrower {
      credit-score: u50,
      total-borrowed: u0,
      collateral-value: u0,
      liquidation-risk: u0,
      last-assessment: block-height,
      default-history: u0
    })
    (ok true)))

(define-public (update-asset-price (asset (string-ascii 10)) (price uint) (volatility uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set collateral-assets asset {
      price: price,
      volatility: volatility,
      liquidity-score: u80, ;; Default liquidity score
      risk-weight: (if (> volatility VOLATILITY-LIMIT) u150 u100),
      last-update: block-height
    })
    (ok true)))

(define-public (assess-borrowing-risk 
  (borrower principal) 
  (asset (string-ascii 10)) 
  (borrow-amount uint)
  (collateral-amount uint))
  
  (let ((credit-score (calculate-credit-score borrower))
        (asset-risk (assess-volatility-risk asset))
        (ltv-ratio (/ (* borrow-amount u100) collateral-amount))
        (health-factor (calculate-health-factor collateral-amount borrow-amount)))
    
    (asserts! (< ltv-ratio MAX-LTV-RATIO) ERR-INSUFFICIENT-COLLATERAL)
    (asserts! (> health-factor u100) ERR-RISK-TOO-HIGH)
    (asserts! (< asset-risk u50) ERR-MARKET-VOLATILITY)
    
    ;; Update position
    (map-set lending-positions { borrower: borrower, asset: asset } {
      borrowed-amount: borrow-amount,
      collateral-amount: collateral-amount,
      ltv-ratio: ltv-ratio,
      health-factor: health-factor,
      created-at: block-height
    })
    
    (ok { 
      risk-score: (/ (+ credit-score asset-risk) u2),
      ltv-ratio: ltv-ratio,
      health-factor: health-factor,
      approved: true
    })))


