;; PBM Optimizer Smart Contract
;; Transparent pharmacy benefit management platform eliminating spread pricing and rebate opacity
;; while optimizing drug costs for employers and patients

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))
(define-constant ERR-UNAUTHORIZED (err u105))
(define-constant ERR-INVALID-STATUS (err u106))

;; Data Variables
(define-data-var total-employers uint u0)
(define-data-var total-patients uint u0)
(define-data-var total-pharmacies uint u0)
(define-data-var total-claims-processed uint u0)
(define-data-var total-savings uint u0)

;; Data Maps

;; Employer registry with benefit plan details
(define-map employers
    principal
    {
        name: (string-ascii 100),
        plan-id: uint,
        employees: uint,
        monthly-premium: uint,
        formulary-tier: uint,
        active: bool,
        total-claims: uint,
        total-paid: uint
    }
)

;; Patient registry with coverage details
(define-map patients
    principal
    {
        employer: principal,
        member-id: (string-ascii 50),
        plan-tier: uint,
        deductible-remaining: uint,
        copay-tier: uint,
        active: bool,
        total-claims: uint
    }
)

;; Pharmacy network with pricing transparency
(define-map pharmacies
    principal
    {
        name: (string-ascii 100),
        npi: (string-ascii 20),
        network-status: uint,
        average-discount: uint,
        claims-processed: uint,
        total-dispensed: uint,
        active: bool
    }
)

;; Drug formulary with transparent pricing
(define-map drug-formulary
    (string-ascii 100) ;; drug-ndc
    {
        generic-name: (string-ascii 100),
        brand-name: (string-ascii 100),
        tier: uint,
        wholesale-price: uint,
        retail-price: uint,
        copay-amount: uint,
        prior-auth-required: bool,
        preferred: bool
    }
)

;; Claims processing with transparent adjudication
(define-map claims
    uint ;; claim-id
    {
        patient: principal,
        pharmacy: principal,
        drug-ndc: (string-ascii 100),
        quantity: uint,
        days-supply: uint,
        submitted-amount: uint,
        approved-amount: uint,
        patient-copay: uint,
        plan-payment: uint,
        status: uint, ;; 0=submitted, 1=approved, 2=rejected, 3=paid
        timestamp: uint,
        savings-generated: uint
    }
)

;; Prior authorization requests
(define-map prior-authorizations
    uint ;; auth-id
    {
        patient: principal,
        prescriber: principal,
        drug-ndc: (string-ascii 100),
        diagnosis-code: (string-ascii 20),
        clinical-rationale: (string-ascii 500),
        status: uint, ;; 0=pending, 1=approved, 2=denied
        expiry-date: uint,
        timestamp: uint
    }
)

;; Rebate tracking for transparency
(define-map rebate-tracking
    { employer: principal, quarter: uint }
    {
        total-rebates-earned: uint,
        rebates-passed-through: uint,
        administrative-fees: uint,
        net-savings: uint
    }
)

;; Public Functions

;; Register new employer with benefit plan
(define-public (register-employer (name (string-ascii 100)) (employees uint) (monthly-premium uint) (formulary-tier uint))
    (let
        (
            (plan-id (+ (var-get total-employers) u1))
        )
        (asserts! (is-none (map-get? employers tx-sender)) ERR-ALREADY-EXISTS)
        (asserts! (> employees u0) ERR-INVALID-AMOUNT)
        (asserts! (> monthly-premium u0) ERR-INVALID-AMOUNT)
        
        (map-set employers tx-sender
            {
                name: name,
                plan-id: plan-id,
                employees: employees,
                monthly-premium: monthly-premium,
                formulary-tier: formulary-tier,
                active: true,
                total-claims: u0,
                total-paid: u0
            }
        )
        
        (var-set total-employers (+ (var-get total-employers) u1))
        (ok plan-id)
    )
)

;; Register patient under employer plan
(define-public (register-patient (employer principal) (member-id (string-ascii 50)) (plan-tier uint) (deductible uint) (copay-tier uint))
    (let
        (
            (employer-data (unwrap! (map-get? employers employer) ERR-NOT-FOUND))
        )
        (asserts! (get active employer-data) ERR-INVALID-STATUS)
        (asserts! (is-none (map-get? patients tx-sender)) ERR-ALREADY-EXISTS)
        
        (map-set patients tx-sender
            {
                employer: employer,
                member-id: member-id,
                plan-tier: plan-tier,
                deductible-remaining: deductible,
                copay-tier: copay-tier,
                active: true,
                total-claims: u0
            }
        )
        
        (var-set total-patients (+ (var-get total-patients) u1))
        (ok true)
    )
)

;; Register pharmacy in network
(define-public (register-pharmacy (name (string-ascii 100)) (npi (string-ascii 20)) (network-status uint) (average-discount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
        (asserts! (is-none (map-get? pharmacies tx-sender)) ERR-ALREADY-EXISTS)
        
        (map-set pharmacies tx-sender
            {
                name: name,
                npi: npi,
                network-status: network-status,
                average-discount: average-discount,
                claims-processed: u0,
                total-dispensed: u0,
                active: true
            }
        )
        
        (var-set total-pharmacies (+ (var-get total-pharmacies) u1))
        (ok true)
    )
)

;; Add drug to formulary with transparent pricing
(define-public (add-drug-to-formulary (drug-ndc (string-ascii 100)) (generic-name (string-ascii 100)) (brand-name (string-ascii 100)) 
                                     (tier uint) (wholesale-price uint) (retail-price uint) (copay-amount uint) 
                                     (prior-auth-required bool) (preferred bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
        (asserts! (> wholesale-price u0) ERR-INVALID-AMOUNT)
        (asserts! (> retail-price u0) ERR-INVALID-AMOUNT)
        
        (map-set drug-formulary drug-ndc
            {
                generic-name: generic-name,
                brand-name: brand-name,
                tier: tier,
                wholesale-price: wholesale-price,
                retail-price: retail-price,
                copay-amount: copay-amount,
                prior-auth-required: prior-auth-required,
                preferred: preferred
            }
        )
        
        (ok true)
    )
)

;; Submit pharmacy claim for processing
(define-public (submit-claim (pharmacy principal) (drug-ndc (string-ascii 100)) (quantity uint) 
                            (days-supply uint) (submitted-amount uint))
    (let
        (
            (claim-id (+ (var-get total-claims-processed) u1))
            (patient-data (unwrap! (map-get? patients tx-sender) ERR-NOT-FOUND))
            (pharmacy-data (unwrap! (map-get? pharmacies pharmacy) ERR-NOT-FOUND))
            (drug-data (unwrap! (map-get? drug-formulary drug-ndc) ERR-NOT-FOUND))
            (calculated-copay (get copay-amount drug-data))
            (plan-payment (- submitted-amount calculated-copay))
            (savings (- (get retail-price drug-data) submitted-amount))
        )
        (asserts! (get active patient-data) ERR-INVALID-STATUS)
        (asserts! (get active pharmacy-data) ERR-INVALID-STATUS)
        (asserts! (> quantity u0) ERR-INVALID-AMOUNT)
        (asserts! (> submitted-amount u0) ERR-INVALID-AMOUNT)
        
        (map-set claims claim-id
            {
                patient: tx-sender,
                pharmacy: pharmacy,
                drug-ndc: drug-ndc,
                quantity: quantity,
                days-supply: days-supply,
                submitted-amount: submitted-amount,
                approved-amount: submitted-amount,
                patient-copay: calculated-copay,
                plan-payment: plan-payment,
                status: u1, ;; approved
                timestamp: stacks-block-height,
                savings-generated: savings
            }
        )
        
        ;; Update counters
        (var-set total-claims-processed (+ (var-get total-claims-processed) u1))
        (var-set total-savings (+ (var-get total-savings) savings))
        
        ;; Update patient record
        (map-set patients tx-sender
            (merge patient-data { total-claims: (+ (get total-claims patient-data) u1) })
        )
        
        ;; Update pharmacy record
        (map-set pharmacies pharmacy
            (merge pharmacy-data 
                { 
                    claims-processed: (+ (get claims-processed pharmacy-data) u1),
                    total-dispensed: (+ (get total-dispensed pharmacy-data) submitted-amount)
                }
            )
        )
        
        (ok claim-id)
    )
)

;; Process rebate distribution with full transparency
(define-public (process-rebate-distribution (employer principal) (quarter uint) (total-rebates uint) (admin-fees uint))
    (let
        (
            (rebates-passed (- total-rebates admin-fees))
            (net-savings rebates-passed)
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
        (asserts! (is-some (map-get? employers employer)) ERR-NOT-FOUND)
        (asserts! (> total-rebates u0) ERR-INVALID-AMOUNT)
        (asserts! (< admin-fees total-rebates) ERR-INVALID-AMOUNT)
        
        (map-set rebate-tracking { employer: employer, quarter: quarter }
            {
                total-rebates-earned: total-rebates,
                rebates-passed-through: rebates-passed,
                administrative-fees: admin-fees,
                net-savings: net-savings
            }
        )
        
        (ok net-savings)
    )
)

;; Read-Only Functions

;; Get employer details
(define-read-only (get-employer (employer principal))
    (map-get? employers employer)
)

;; Get patient details
(define-read-only (get-patient (patient principal))
    (map-get? patients patient)
)

;; Get pharmacy details
(define-read-only (get-pharmacy (pharmacy principal))
    (map-get? pharmacies pharmacy)
)

;; Get drug formulary info
(define-read-only (get-drug-info (drug-ndc (string-ascii 100)))
    (map-get? drug-formulary drug-ndc)
)

;; Get claim details
(define-read-only (get-claim (claim-id uint))
    (map-get? claims claim-id)
)

;; Get rebate tracking info
(define-read-only (get-rebate-info (employer principal) (quarter uint))
    (map-get? rebate-tracking { employer: employer, quarter: quarter })
)

;; Get platform statistics
(define-read-only (get-platform-stats)
    {
        total-employers: (var-get total-employers),
        total-patients: (var-get total-patients),
        total-pharmacies: (var-get total-pharmacies),
        total-claims-processed: (var-get total-claims-processed),
        total-savings: (var-get total-savings)
    }
)

