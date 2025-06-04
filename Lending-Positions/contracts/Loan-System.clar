;; COLLATERAL-BACKED LENDING VAULT SMART CONTRACT
;; Protocol Name: Collateral-Backed Lending Vault (CBLV)
;;
;; Description:
;; The Collateral-Backed Lending Vault is a decentralized money market protocol that
;; enables trustless borrowing and lending through over-collateralized positions.
;; Users can lock STX tokens as collateral to mint stable-value loans while maintaining
;; full custody of their assets until liquidation conditions are met.
;;
;; Core Functionality:
;; Collateral Deposits: Users lock STX tokens to secure borrowing capacity
;; Loan Origination: Borrow up to 66.67% of collateral value (150% collateral ratio)
;; Dynamic Liquidations: Automatic position closure when collateral drops below 130%
;; Fee Mechanism: Protocol sustainability through borrower repayment fees
;; Price Oracle Integration: Real-time collateral valuation for risk management

;; PROTOCOL CONSTANTS

;; System Error Codes
(define-constant AUTHORIZATION_FAILURE u1)
(define-constant INSUFFICIENT_COLLATERAL_BALANCE u2)
(define-constant PROTOCOL_LIQUIDITY_SHORTAGE u3)
(define-constant BELOW_MINIMUM_COLLATERAL_RATIO u4)
(define-constant LENDING_POSITION_DOES_NOT_EXIST u5)
(define-constant LENDING_POSITION_ALREADY_ACTIVE u6)
(define-constant INVALID_TRANSACTION_AMOUNT u7)
(define-constant LIQUIDATION_CRITERIA_NOT_SATISFIED u8)
(define-constant EXCEEDS_MAXIMUM_FEE_LIMIT u9)
(define-constant ZERO_VALUE_NOT_ALLOWED u10)

;; Risk Management Parameters
(define-constant REQUIRED_COLLATERAL_COVERAGE u150) ;; 150% collateral-to-debt ratio
(define-constant LIQUIDATION_TRIGGER_THRESHOLD u130) ;; 130% triggers liquidation
(define-constant MAXIMUM_UINT_VALUE u340282366920938463463374607431768211455)
(define-constant MAXIMUM_ALLOWED_FEE_PERCENTAGE u10) ;; 10% fee ceiling

;; PROTOCOL STATE STORAGE

;; Global Protocol Metrics
(define-data-var governance-authority principal tx-sender)
(define-data-var total-protocol-collateral-locked uint u0)
(define-data-var total-protocol-debt-issued uint u0)
(define-data-var number-of-active-lending-positions uint u0)
(define-data-var borrower-fee-rate uint u1) ;; 1% default

;; Individual Lending Position Records
(define-map lending-position-registry
  { borrower-address: principal }
  {
    stx-collateral-balance: uint,
    outstanding-loan-balance: uint,
    position-last-updated-height: uint
  }
)

;; External Price Feed Registry
(define-map market-price-feeds
  { token-symbol: (string-ascii 32) }
  { price-in-usd-cents: uint }
)

;; INFORMATION RETRIEVAL           

;; Retrieve complete lending position details
(define-read-only (retrieve-lending-position-details (borrower-address principal))
  (map-get? lending-position-registry { borrower-address: borrower-address })
)

;; Get current STX market price from oracle
(define-read-only (retrieve-current-stx-market-price)
  (default-to u100 
    (get price-in-usd-cents 
      (map-get? market-price-feeds { token-symbol: "STX" })))
)

;; Calculate position's collateral coverage ratio
(define-read-only (compute-position-collateral-coverage (borrower-address principal))
  (let (
    (position-record (retrieve-lending-position-details borrower-address))
  )
  (match position-record
    lending-data
    (let (
      (total-collateral-value (* (get stx-collateral-balance lending-data) 
                                 (retrieve-current-stx-market-price)))
      (loan-balance (get outstanding-loan-balance lending-data))
    )
    (if (is-eq loan-balance u0)
      u0
      (/ (* total-collateral-value u100) loan-balance)))
    u0
  ))
)

;; Determine maximum borrowing capacity
(define-read-only (calculate-borrowing-power (borrower-address principal))
  (let (
    (position-record (retrieve-lending-position-details borrower-address))
  )
  (match position-record
    lending-data
    (let (
      (collateral-market-value (* (get stx-collateral-balance lending-data) 
                                  (retrieve-current-stx-market-price)))
    )
    (/ (* collateral-market-value u100) REQUIRED_COLLATERAL_COVERAGE))
    u0
  ))
)

;; Check if position can be liquidated
(define-read-only (is-position-liquidatable (borrower-address principal))
  (let (
    (coverage-ratio (compute-position-collateral-coverage borrower-address))
  )
  (and 
    (> coverage-ratio u0) ;; Active position exists
    (< coverage-ratio LIQUIDATION_TRIGGER_THRESHOLD)
  ))
)

;; Calculate position health score (100% = liquidation threshold)
(define-read-only (calculate-position-health-score (borrower-address principal))
  (let (
    (coverage-ratio (compute-position-collateral-coverage borrower-address))
  )
  (if (is-eq coverage-ratio u0)
    u0
    (/ (* coverage-ratio u100) LIQUIDATION_TRIGGER_THRESHOLD)
  ))
)

;; POSITION MANAGEMENT OPERATIONS

;; Open new lending position
(define-public (open-new-lending-position)
  (let (
    (position-creator tx-sender)
  )
  ;; Verify no existing position
  (asserts! (is-none (retrieve-lending-position-details position-creator)) 
            (err LENDING_POSITION_ALREADY_ACTIVE))
  
  ;; Initialize empty position
  (map-set lending-position-registry
    { borrower-address: position-creator }
    {
      stx-collateral-balance: u0,
      outstanding-loan-balance: u0,
      position-last-updated-height: block-height
    }
  )
  
  ;; Increment position counter
  (var-set number-of-active-lending-positions 
           (+ (var-get number-of-active-lending-positions) u1))
  (ok true))
)

;; Increase collateral in position
(define-public (increase-position-collateral (stx-deposit-amount uint))
  (let (
    (depositor-address tx-sender)
    (existing-position (unwrap! (retrieve-lending-position-details depositor-address) 
                               (err LENDING_POSITION_DOES_NOT_EXIST)))
    (current-collateral-balance (get stx-collateral-balance existing-position))
  )
  ;; Validate deposit amount
  (asserts! (> stx-deposit-amount u0) (err ZERO_VALUE_NOT_ALLOWED))
  
  ;; Check for overflow conditions
  (asserts! (<= (+ current-collateral-balance stx-deposit-amount) MAXIMUM_UINT_VALUE) 
            (err INVALID_TRANSACTION_AMOUNT))
  (asserts! (<= (+ (var-get total-protocol-collateral-locked) stx-deposit-amount) MAXIMUM_UINT_VALUE) 
            (err INVALID_TRANSACTION_AMOUNT))
  
  ;; Transfer STX to protocol vault
  (try! (stx-transfer? stx-deposit-amount depositor-address (as-contract tx-sender)))
  
  ;; Update position record
  (map-set lending-position-registry
    { borrower-address: depositor-address }
    {
      stx-collateral-balance: (+ current-collateral-balance stx-deposit-amount),
      outstanding-loan-balance: (get outstanding-loan-balance existing-position),
      position-last-updated-height: block-height
    }
  )
  
  ;; Update protocol metrics
  (var-set total-protocol-collateral-locked 
           (+ (var-get total-protocol-collateral-locked) stx-deposit-amount))
  (ok true))
)

;; Withdraw excess collateral
(define-public (withdraw-excess-collateral (stx-withdrawal-amount uint))
  (let (
    (withdrawer-address tx-sender)
    (existing-position (unwrap! (retrieve-lending-position-details withdrawer-address) 
                               (err LENDING_POSITION_DOES_NOT_EXIST)))
    (current-collateral-balance (get stx-collateral-balance existing-position))
    (current-loan-balance (get outstanding-loan-balance existing-position))
  )
    ;; Validate withdrawal amount
    (asserts! (> stx-withdrawal-amount u0) (err ZERO_VALUE_NOT_ALLOWED))
    (asserts! (<= stx-withdrawal-amount current-collateral-balance) 
              (err INSUFFICIENT_COLLATERAL_BALANCE))
    
    ;; Calculate post-withdrawal position health
    (let (
      (post-withdrawal-collateral (- current-collateral-balance stx-withdrawal-amount))
      (post-withdrawal-collateral-value (* post-withdrawal-collateral 
                                          (retrieve-current-stx-market-price)))
      (resulting-coverage-ratio (if (is-eq current-loan-balance u0)
                                   u0
                                   (/ (* post-withdrawal-collateral-value u100) 
                                      current-loan-balance)))
    )
      ;; Ensure position remains healthy
      (asserts! (or (is-eq current-loan-balance u0) 
                    (>= resulting-coverage-ratio REQUIRED_COLLATERAL_COVERAGE)) 
                (err BELOW_MINIMUM_COLLATERAL_RATIO))
      
      ;; Transfer STX back to user
      (try! (as-contract (stx-transfer? stx-withdrawal-amount 
                                       (as-contract tx-sender) 
                                       withdrawer-address)))
      
      ;; Update position record
      (map-set lending-position-registry
        { borrower-address: withdrawer-address }
        {
          stx-collateral-balance: post-withdrawal-collateral,
          outstanding-loan-balance: current-loan-balance,
          position-last-updated-height: block-height
        }
      )
      
      ;; Update protocol metrics
      (var-set total-protocol-collateral-locked 
               (- (var-get total-protocol-collateral-locked) stx-withdrawal-amount))
      (ok true)
    ))
)

;; BORROWING AND REPAYMENT

;; Take out loan against collateral
(define-public (originate-collateralized-loan (requested-loan-amount uint))
  (let (
    (loan-applicant tx-sender)
    (existing-position (unwrap! (retrieve-lending-position-details loan-applicant) 
                               (err LENDING_POSITION_DOES_NOT_EXIST)))
    (position-collateral (get stx-collateral-balance existing-position))
    (current-debt (get outstanding-loan-balance existing-position))
  )
  ;; Validate loan amount
  (asserts! (> requested-loan-amount u0) (err ZERO_VALUE_NOT_ALLOWED))
  
  ;; Check for overflow
  (asserts! (<= (+ current-debt requested-loan-amount) MAXIMUM_UINT_VALUE) 
            (err INVALID_TRANSACTION_AMOUNT))
  
  ;; Verify borrowing capacity
  (let (
    (collateral-usd-value (* position-collateral (retrieve-current-stx-market-price)))
    (maximum-loan-capacity (/ (* collateral-usd-value u100) REQUIRED_COLLATERAL_COVERAGE))
    (new-total-debt (+ current-debt requested-loan-amount))
  )
    ;; Ensure loan doesn't exceed capacity
    (asserts! (<= new-total-debt maximum-loan-capacity) 
              (err BELOW_MINIMUM_COLLATERAL_RATIO))
    
    ;; Check protocol has liquidity
    (asserts! (<= requested-loan-amount (stx-get-balance (as-contract tx-sender))) 
              (err PROTOCOL_LIQUIDITY_SHORTAGE))
    
    ;; Disburse loan funds
    (try! (as-contract (stx-transfer? requested-loan-amount 
                                     (as-contract tx-sender) 
                                     loan-applicant)))
    
    ;; Update position record
    (map-set lending-position-registry
      { borrower-address: loan-applicant }
      {
        stx-collateral-balance: position-collateral,
        outstanding-loan-balance: new-total-debt,
        position-last-updated-height: block-height
      }
    )
    
    ;; Update protocol debt metrics
    (var-set total-protocol-debt-issued 
             (+ (var-get total-protocol-debt-issued) requested-loan-amount))
    (ok true)
  ))
)

;; Repay outstanding loan
(define-public (submit-loan-repayment (repayment-amount uint))
  (let (
    (repayer-address tx-sender)
    (existing-position (unwrap! (retrieve-lending-position-details repayer-address) 
                               (err LENDING_POSITION_DOES_NOT_EXIST)))
    (current-debt-balance (get outstanding-loan-balance existing-position))
  )
  ;; Validate repayment amount
  (asserts! (> repayment-amount u0) (err ZERO_VALUE_NOT_ALLOWED))
  
  ;; Calculate repayment allocation
  (let (
    (effective-repayment (if (> repayment-amount current-debt-balance) 
                            current-debt-balance 
                            repayment-amount))
    (protocol-fee-collection (/ (* effective-repayment (var-get borrower-fee-rate)) u100))
    (principal-repayment (- effective-repayment protocol-fee-collection))
  )
    ;; Process repayment transfer
    (try! (stx-transfer? effective-repayment repayer-address (as-contract tx-sender)))
    
    ;; Update position record
    (map-set lending-position-registry
      { borrower-address: repayer-address }
      {
        stx-collateral-balance: (get stx-collateral-balance existing-position),
        outstanding-loan-balance: (- current-debt-balance principal-repayment),
        position-last-updated-height: block-height
      }
    )
    
    ;; Update protocol debt metrics
    (var-set total-protocol-debt-issued 
             (- (var-get total-protocol-debt-issued) principal-repayment))
    (ok true)
  ))
)

;; LIQUIDATION MECHANISM 

;; Liquidate underwater position
(define-public (liquidate-underwater-position (target-borrower principal))
  (let (
    (liquidation-executor tx-sender)
    (target-position (unwrap! (retrieve-lending-position-details target-borrower) 
                             (err LENDING_POSITION_DOES_NOT_EXIST)))
    (seized-collateral (get stx-collateral-balance target-position))
    (outstanding-debt (get outstanding-loan-balance target-position))
  )
  ;; Validate position has assets
  (asserts! (> seized-collateral u0) (err INVALID_TRANSACTION_AMOUNT))
  (asserts! (> outstanding-debt u0) (err INVALID_TRANSACTION_AMOUNT))
  
  ;; Verify liquidation conditions
  (let (
    (collateral-market-value (* seized-collateral (retrieve-current-stx-market-price)))
    (current-coverage-ratio (/ (* collateral-market-value u100) outstanding-debt))
  )
    ;; Must be below liquidation threshold
    (asserts! (< current-coverage-ratio LIQUIDATION_TRIGGER_THRESHOLD) 
              (err LIQUIDATION_CRITERIA_NOT_SATISFIED))
    
    ;; Liquidator repays the debt
    (try! (stx-transfer? outstanding-debt liquidation-executor (as-contract tx-sender)))
    
    ;; Liquidator claims all collateral (includes incentive)
    (try! (as-contract (stx-transfer? seized-collateral 
                                     (as-contract tx-sender) 
                                     liquidation-executor)))
    
    ;; Clear the liquidated position
    (map-set lending-position-registry
      { borrower-address: target-borrower }
      {
        stx-collateral-balance: u0,
        outstanding-loan-balance: u0,
        position-last-updated-height: block-height
      }
    )
    
    ;; Update protocol metrics
    (var-set total-protocol-collateral-locked 
             (- (var-get total-protocol-collateral-locked) seized-collateral))
    (var-set total-protocol-debt-issued 
             (- (var-get total-protocol-debt-issued) outstanding-debt))
    (ok true)
  ))
)


;; GOVERNANCE & ADMINISTRATION

;; Update market price oracle
(define-public (update-market-price-oracle (token-symbol (string-ascii 32)) (new-price-cents uint))
  (begin
    ;; Verify governance authority
    (asserts! (is-eq tx-sender (var-get governance-authority)) 
              (err AUTHORIZATION_FAILURE))
    
    ;; Validate inputs
    (asserts! (> new-price-cents u0) (err ZERO_VALUE_NOT_ALLOWED))
    (asserts! (> (len token-symbol) u0) (err INVALID_TRANSACTION_AMOUNT))
    
    ;; Update price feed
    (map-set market-price-feeds 
      { token-symbol: token-symbol } 
      { price-in-usd-cents: new-price-cents }
    )
    (ok true)
  )
)

;; Modify protocol fee structure
(define-public (modify-borrower-fee-percentage (new-fee-percentage uint))
  (begin
    ;; Verify governance authority
    (asserts! (is-eq tx-sender (var-get governance-authority)) 
              (err AUTHORIZATION_FAILURE))
    
    ;; Enforce fee ceiling
    (asserts! (<= new-fee-percentage MAXIMUM_ALLOWED_FEE_PERCENTAGE) 
              (err EXCEEDS_MAXIMUM_FEE_LIMIT))
    
    ;; Apply new fee rate
    (var-set borrower-fee-rate new-fee-percentage)
    (ok true))
)

;; Transfer governance control
(define-public (transfer-governance-control (new-governance-address principal))
  (begin
    ;; Verify current governance
    (asserts! (is-eq tx-sender (var-get governance-authority)) 
              (err AUTHORIZATION_FAILURE))
    
    ;; Prevent null address assignment
    (asserts! (not (is-eq new-governance-address 'SP000000000000000000002Q6VF78)) 
              (err AUTHORIZATION_FAILURE))
    
    ;; Execute governance transfer
    (var-set governance-authority new-governance-address)
    (ok true))
)

;; PROTOCOL ANALYTICS                                 

;; Get comprehensive protocol statistics
(define-read-only (fetch-protocol-analytics)
  {
    total-value-locked: (var-get total-protocol-collateral-locked),
    total-debt-outstanding: (var-get total-protocol-debt-issued),
    active-positions-count: (var-get number-of-active-lending-positions),
    protocol-fee-percentage: (var-get borrower-fee-rate),
    governance-address: (var-get governance-authority),
    utilization-rate: (calculate-protocol-utilization),
    collateral-price-usd: (retrieve-current-stx-market-price)
  }
)

;; Calculate protocol utilization percentage
(define-read-only (calculate-protocol-utilization)
  (let (
    (total-collateral-value (* (var-get total-protocol-collateral-locked) 
                               (retrieve-current-stx-market-price)))
    (total-debt (var-get total-protocol-debt-issued))
  )
  (if (is-eq total-collateral-value u0)
    u0
    (/ (* total-debt u100) total-collateral-value)
  ))
)

;; Get detailed position information
(define-read-only (fetch-detailed-position-info (borrower-address principal))
  (let (
    (position (retrieve-lending-position-details borrower-address))
  )
  (match position
    position-data
    {
      collateral-stx: (get stx-collateral-balance position-data),
      debt-outstanding: (get outstanding-loan-balance position-data),
      last-interaction: (get position-last-updated-height position-data),
      health-factor: (calculate-position-health-score borrower-address),
      coverage-ratio: (compute-position-collateral-coverage borrower-address),
      borrowing-capacity: (calculate-borrowing-power borrower-address),
      is-liquidatable: (is-position-liquidatable borrower-address)
    }
    {
      collateral-stx: u0,
      debt-outstanding: u0,
      last-interaction: u0,
      health-factor: u0,
      coverage-ratio: u0,
      borrowing-capacity: u0,
      is-liquidatable: false
    }
  ))
)