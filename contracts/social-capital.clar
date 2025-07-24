;; Social Capital Development Contract
;; Builds networks of trust and reciprocity within communities

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INVALID-INPUT (err u401))
(define-constant ERR-RELATIONSHIP-EXISTS (err u402))
(define-constant ERR-RELATIONSHIP-NOT-FOUND (err u403))
(define-constant ERR-CANNOT-CONNECT-SELF (err u404))
(define-constant ERR-INSUFFICIENT-CREDITS (err u405))

;; Data Variables
(define-data-var next-connection-id uint u1)
(define-data-var next-favor-id uint u1)

;; Data Maps
(define-map social-connections
  { connection-id: uint }
  {
    person-a: principal,
    person-b: principal,
    connection-type: (string-ascii 30),
    strength: uint,
    created-at: uint,
    last-interaction: uint,
    mutual-favors: uint,
    active: bool
  }
)

(define-map connection-lookup
  { person-a: principal, person-b: principal }
  { connection-id: uint }
)

(define-map social-credits
  { member: principal }
  {
    credits-earned: uint,
    credits-spent: uint,
    current-balance: uint,
    reputation-score: uint,
    total-favors-given: uint,
    total-favors-received: uint
  }
)

(define-map favor-requests
  { favor-id: uint }
  {
    requester: principal,
    title: (string-ascii 100),
    description: (string-ascii 300),
    credit-value: uint,
    status: (string-ascii 20),
    fulfiller: (optional principal),
    created-at: uint,
    fulfilled-at: (optional uint),
    category: (string-ascii 30)
  }
)

(define-map trust-endorsements
  { endorser: principal, endorsed: principal }
  {
    trust-level: uint,
    endorsement-message: (string-ascii 200),
    created-at: uint,
    category: (string-ascii 30)
  }
)

(define-map network-metrics
  { member: principal }
  {
    direct-connections: uint,
    network-reach: uint,
    influence-score: uint,
    reciprocity-ratio: uint
  }
)

;; Public Functions

;; Create a social connection between two community members
(define-public (create-connection (other-person principal) (connection-type (string-ascii 30)))
  (let ((caller tx-sender)
        (connection-id (var-get next-connection-id)))
    (asserts! (not (is-eq caller other-person)) ERR-CANNOT-CONNECT-SELF)
    (asserts! (> (len connection-type) u0) ERR-INVALID-INPUT)

    ;; Check if connection already exists (bidirectional)
    (asserts! (and (is-none (map-get? connection-lookup { person-a: caller, person-b: other-person }))
                   (is-none (map-get? connection-lookup { person-a: other-person, person-b: caller })))
              ERR-RELATIONSHIP-EXISTS)

    (map-set social-connections
      { connection-id: connection-id }
      {
        person-a: caller,
        person-b: other-person,
        connection-type: connection-type,
        strength: u1,
        created-at: block-height,
        last-interaction: block-height,
        mutual-favors: u0,
        active: true
      }
    )

    ;; Create bidirectional lookup
    (map-set connection-lookup
      { person-a: caller, person-b: other-person }
      { connection-id: connection-id }
    )
    (map-set connection-lookup
      { person-a: other-person, person-b: caller }
      { connection-id: connection-id }
    )

    (var-set next-connection-id (+ connection-id u1))
    (update-network-metrics caller)
    (update-network-metrics other-person)
    (ok connection-id)
  )
)

;; Request a favor from the community
(define-public (request-favor (title (string-ascii 100)) (description (string-ascii 300)) (credit-value uint) (category (string-ascii 30)))
  (let ((caller tx-sender)
        (favor-id (var-get next-favor-id)))
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> credit-value u0) ERR-INVALID-INPUT)

    ;; Initialize social credits if not exists
    (if (is-none (map-get? social-credits { member: caller }))
      (map-set social-credits
        { member: caller }
        {
          credits-earned: u0,
          credits-spent: u0,
          current-balance: u0,
          reputation-score: u50,
          total-favors-given: u0,
          total-favors-received: u0
        }
      )
      true
    )

    (map-set favor-requests
      { favor-id: favor-id }
      {
        requester: caller,
        title: title,
        description: description,
        credit-value: credit-value,
        status: "open",
        fulfiller: none,
        created-at: block-height,
        fulfilled-at: none,
        category: category
      }
    )

    (var-set next-favor-id (+ favor-id u1))
    (ok favor-id)
  )
)

;; Fulfill a favor request
(define-public (fulfill-favor (favor-id uint))
  (let ((caller tx-sender)
        (favor (unwrap! (map-get? favor-requests { favor-id: favor-id }) ERR-RELATIONSHIP-NOT-FOUND)))
    (asserts! (not (is-eq caller (get requester favor))) ERR-CANNOT-CONNECT-SELF)
    (asserts! (is-eq (get status favor) "open") ERR-INVALID-INPUT)

    (map-set favor-requests
      { favor-id: favor-id }
      (merge favor {
        status: "fulfilled",
        fulfiller: (some caller),
        fulfilled-at: (some block-height)
      })
    )

    ;; Update social credits
    (award-social-credits caller (get credit-value favor))
    (update-connection-strength caller (get requester favor))

    (ok true)
  )
)

;; Endorse someone's trustworthiness
(define-public (endorse-trust (endorsed-person principal) (trust-level uint) (message (string-ascii 200)) (category (string-ascii 30)))
  (let ((caller tx-sender))
    (asserts! (not (is-eq caller endorsed-person)) ERR-CANNOT-CONNECT-SELF)
    (asserts! (and (>= trust-level u1) (<= trust-level u5)) ERR-INVALID-INPUT)

    (map-set trust-endorsements
      { endorser: caller, endorsed: endorsed-person }
      {
        trust-level: trust-level,
        endorsement-message: message,
        created-at: block-height,
        category: category
      }
    )

    (update-reputation-score endorsed-person)
    (ok true)
  )
)

;; Spend social credits for community benefits
(define-public (spend-social-credits (amount uint) (purpose (string-ascii 100)))
  (let ((caller tx-sender)
        (credits (unwrap! (map-get? social-credits { member: caller }) ERR-RELATIONSHIP-NOT-FOUND)))
    (asserts! (>= (get current-balance credits) amount) ERR-INSUFFICIENT-CREDITS)
    (asserts! (> amount u0) ERR-INVALID-INPUT)

    (map-set social-credits
      { member: caller }
      (merge credits {
        credits-spent: (+ (get credits-spent credits) amount),
        current-balance: (- (get current-balance credits) amount)
      })
    )

    (ok true)
  )
)

;; Strengthen a connection through interaction
(define-public (strengthen-connection (other-person principal))
  (let ((caller tx-sender))
    (asserts! (not (is-eq caller other-person)) ERR-CANNOT-CONNECT-SELF)

    (update-connection-strength caller other-person)
    (ok true)
  )
)

;; Read-only Functions

;; Get social connection
(define-read-only (get-social-connection (connection-id uint))
  (map-get? social-connections { connection-id: connection-id })
)

;; Get connection between two people
(define-read-only (get-connection-between (person-a principal) (person-b principal))
  (match (map-get? connection-lookup { person-a: person-a, person-b: person-b })
    lookup-data (map-get? social-connections { connection-id: (get connection-id lookup-data) })
    none
  )
)

;; Get social credits
(define-read-only (get-social-credits (member principal))
  (map-get? social-credits { member: member })
)

;; Get favor request
(define-read-only (get-favor-request (favor-id uint))
  (map-get? favor-requests { favor-id: favor-id })
)

;; Get trust endorsement
(define-read-only (get-trust-endorsement (endorser principal) (endorsed principal))
  (map-get? trust-endorsements { endorser: endorser, endorsed: endorsed })
)

;; Get network metrics
(define-read-only (get-network-metrics (member principal))
  (map-get? network-metrics { member: member })
)

;; Check if two people are connected
(define-read-only (are-connected (person-a principal) (person-b principal))
  (is-some (map-get? connection-lookup { person-a: person-a, person-b: person-b }))
)

;; Private Functions

;; Award social credits to a member
(define-private (award-social-credits (member principal) (amount uint))
  (let ((current-credits (default-to
                         {
                           credits-earned: u0,
                           credits-spent: u0,
                           current-balance: u0,
                           reputation-score: u50,
                           total-favors-given: u0,
                           total-favors-received: u0
                         }
                         (map-get? social-credits { member: member }))))
    (map-set social-credits
      { member: member }
      (merge current-credits {
        credits-earned: (+ (get credits-earned current-credits) amount),
        current-balance: (+ (get current-balance current-credits) amount),
        total-favors-given: (+ (get total-favors-given current-credits) u1)
      })
    )
  )
)

;; Update connection strength between two people
(define-private (update-connection-strength (person-a principal) (person-b principal))
  (match (map-get? connection-lookup { person-a: person-a, person-b: person-b })
    lookup-data
      (match (map-get? social-connections { connection-id: (get connection-id lookup-data) })
        connection
          (let ((new-strength (+ (get strength connection) u1)))
            (map-set social-connections
              { connection-id: (get connection-id lookup-data) }
              (merge connection {
                strength: (if (> new-strength u10) u10 new-strength),
                last-interaction: block-height,
                mutual-favors: (+ (get mutual-favors connection) u1)
              })
            ))
        false
      )
    false
  )
)

;; Update reputation score based on endorsements
(define-private (update-reputation-score (member principal))
  (let ((current-credits (default-to
                         {
                           credits-earned: u0,
                           credits-spent: u0,
                           current-balance: u0,
                           reputation-score: u50,
                           total-favors-given: u0,
                           total-favors-received: u0
                         }
                         (map-get? social-credits { member: member }))))
    (let ((new-score (+ (get reputation-score current-credits) u5)))
      (map-set social-credits
        { member: member }
        (merge current-credits {
          reputation-score: (if (> new-score u100) u100 new-score)
        })
      ))
  )
)

;; Update network metrics for a member
(define-private (update-network-metrics (member principal))
  (let ((current-metrics (default-to
                         {
                           direct-connections: u0,
                           network-reach: u0,
                           influence-score: u0,
                           reciprocity-ratio: u50
                         }
                         (map-get? network-metrics { member: member }))))
    (map-set network-metrics
      { member: member }
      (merge current-metrics {
        direct-connections: (+ (get direct-connections current-metrics) u1),
        influence-score: (calculate-influence-score member)
      })
    )
  )
)

;; Calculate influence score (simplified)
(define-private (calculate-influence-score (member principal))
  (match (map-get? social-credits { member: member })
    credits (+ (get reputation-score credits) (get total-favors-given credits))
    u0
  )
)
