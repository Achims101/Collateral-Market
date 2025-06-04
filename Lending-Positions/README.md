# Collateral-Backed Lending Vault (CBLV) Smart Contract

A decentralized money market protocol built on Stacks that enables trustless borrowing and lending through over-collateralized positions using STX tokens.

## Overview

The Collateral-Backed Lending Vault allows users to:
- Lock STX tokens as collateral
- Borrow against their collateral up to 66.67% of its value (150% collateral ratio)
- Maintain full custody of assets until liquidation conditions are met
- Participate in a decentralized lending ecosystem with automatic risk management

## Key Features

### Over-Collateralized Lending
- **150% Minimum Collateral Ratio**: Borrow up to 66.67% of your STX collateral value
- **Dynamic Risk Management**: Real-time position monitoring with price oracle integration
- **Liquidation Protection**: Automatic position closure at 130% collateral ratio

### Core Functionality
- **Collateral Management**: Deposit and withdraw STX collateral
- **Loan Origination**: Borrow STX against locked collateral
- **Flexible Repayment**: Repay loans with built-in fee mechanism
- **Liquidation System**: Automated liquidation for underwater positions

### Analytics & Monitoring
- Real-time position health scoring
- Protocol utilization metrics
- Comprehensive position analytics

## Protocol Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Minimum Collateral Ratio | 150% | Required collateral coverage for new loans |
| Liquidation Threshold | 130% | Positions below this ratio can be liquidated |
| Maximum Fee Rate | 10% | Cap on protocol fees |
| Default Borrower Fee | 1% | Fee charged on loan repayments |

## Smart Contract Functions

### Position Management

#### `open-new-lending-position()`
Creates a new lending position for the caller.
- **Requirements**: Caller must not have an existing position
- **Returns**: `(ok true)` on success

#### `increase-position-collateral(stx-deposit-amount)`
Adds STX collateral to an existing position.
- **Parameters**: 
  - `stx-deposit-amount` (uint): Amount of STX to deposit
- **Requirements**: Must have existing position, amount > 0

#### `withdraw-excess-collateral(stx-withdrawal-amount)`
Withdraws collateral while maintaining minimum collateral ratio.
- **Parameters**:
  - `stx-withdrawal-amount` (uint): Amount of STX to withdraw
- **Requirements**: Must maintain 150% collateral ratio after withdrawal

### Borrowing & Repayment

#### `originate-collateralized-loan(requested-loan-amount)`
Borrows STX against locked collateral.
- **Parameters**:
  - `requested-loan-amount` (uint): Amount of STX to borrow
- **Requirements**: Must maintain 150% collateral ratio, sufficient protocol liquidity

#### `submit-loan-repayment(repayment-amount)`
Repays outstanding loan with fees.
- **Parameters**:
  - `repayment-amount` (uint): Amount of STX to repay
- **Fee Structure**: 1% default fee on repayments

### Liquidations

#### `liquidate-underwater-position(target-borrower)`
Liquidates positions below 130% collateral ratio.
- **Parameters**:
  - `target-borrower` (principal): Address of position to liquidate
- **Incentive**: Liquidator receives all collateral after repaying debt
- **Requirements**: Position must be below liquidation threshold

### Read-Only Functions

#### Position Information
- `retrieve-lending-position-details(borrower-address)`: Get complete position data
- `compute-position-collateral-coverage(borrower-address)`: Calculate collateral ratio
- `calculate-borrowing-power(borrower-address)`: Determine max borrowing capacity
- `is-position-liquidatable(borrower-address)`: Check liquidation eligibility
- `calculate-position-health-score(borrower-address)`: Get position health (100% = liquidation threshold)

#### Protocol Analytics
- `fetch-protocol-analytics()`: Comprehensive protocol statistics
- `calculate-protocol-utilization()`: Current utilization percentage
- `fetch-detailed-position-info(borrower-address)`: Detailed position analytics

### Governance Functions

#### `update-market-price-oracle(token-symbol, new-price-cents)`
Updates price feed for market assets.
- **Access**: Governance only
- **Parameters**:
  - `token-symbol` (string-ascii 32): Asset symbol (e.g., "STX")
  - `new-price-cents` (uint): New price in USD cents

#### `modify-borrower-fee-percentage(new-fee-percentage)`
Adjusts protocol fee structure.
- **Access**: Governance only
- **Parameters**:
  - `new-fee-percentage` (uint): New fee percentage (max 10%)

#### `transfer-governance-control(new-governance-address)`
Transfers governance authority.
- **Access**: Current governance only
- **Parameters**:
  - `new-governance-address` (principal): New governance address

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| u1 | AUTHORIZATION_FAILURE | Insufficient permissions |
| u2 | INSUFFICIENT_COLLATERAL_BALANCE | Not enough collateral |
| u3 | PROTOCOL_LIQUIDITY_SHORTAGE | Protocol lacks liquidity |
| u4 | BELOW_MINIMUM_COLLATERAL_RATIO | Position would be undercollateralized |
| u5 | LENDING_POSITION_DOES_NOT_EXIST | Position not found |
| u6 | LENDING_POSITION_ALREADY_ACTIVE | Position already exists |
| u7 | INVALID_TRANSACTION_AMOUNT | Invalid amount specified |
| u8 | LIQUIDATION_CRITERIA_NOT_SATISFIED | Position not eligible for liquidation |
| u9 | EXCEEDS_MAXIMUM_FEE_LIMIT | Fee exceeds 10% limit |
| u10 | ZERO_VALUE_NOT_ALLOWED | Zero values not permitted |

## Usage Examples

### Opening a Position and Borrowing

```clarity
;; 1. Open a new lending position
(contract-call? .cblv open-new-lending-position)

;; 2. Deposit 1000 STX as collateral
(contract-call? .cblv increase-position-collateral u1000000000) ;; 1000 STX in microSTX

;; 3. Borrow 400 STX (assuming STX price allows this ratio)
(contract-call? .cblv originate-collateralized-loan u400000000) ;; 400 STX in microSTX
```

### Monitoring Position Health

```clarity
;; Check your position details
(contract-call? .cblv fetch-detailed-position-info tx-sender)

;; Check if position is liquidatable
(contract-call? .cblv is-position-liquidatable tx-sender)

;; Get current collateral ratio
(contract-call? .cblv compute-position-collateral-coverage tx-sender)
```

### Repaying Loans

```clarity
;; Repay 200 STX (partial repayment)
(contract-call? .cblv submit-loan-repayment u200000000)
```

## Risk Management

- **Collateral Monitoring**: Continuously monitor your position's health score
- **Price Volatility**: STX price changes directly affect your collateral ratio
- **Liquidation Risk**: Positions below 130% collateral ratio face liquidation
- **Fee Consideration**: Factor in 1% repayment fees when borrowing

## Security Considerations

- Over-collateralization protects the protocol from bad debt
- Price oracle dependency requires trusted price feeds
- Liquidation mechanism provides protocol solvency
- Governance controls critical protocol parameters

## Protocol Statistics

Access real-time protocol data:
- Total Value Locked (TVL)
- Total Outstanding Debt
- Number of Active Positions
- Protocol Utilization Rate
- Current STX Price