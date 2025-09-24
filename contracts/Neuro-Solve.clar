;; Neuro-Solve: Decentralized Neurological Research Platform
;; A blockchain-based platform for collaborative neurological research and problem-solving
;; Version: 1.0.0
;; Compatible with: Clarinet 3.x

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_CHALLENGE_NOT_FOUND (err u404))
(define-constant ERR_SOLUTION_NOT_FOUND (err u405))
(define-constant ERR_INSUFFICIENT_PAYMENT (err u402))
(define-constant ERR_INVALID_PARAMETERS (err u400))
(define-constant ERR_ALREADY_VOTED (err u409))
(define-constant ERR_CHALLENGE_EXPIRED (err u408))
(define-constant ERR_INVALID_STATUS (err u407))

;; Data Variables
(define-data-var challenge-counter uint u0)
(define-data-var solution-counter uint u0)
(define-data-var platform-fee-percentage uint u10) ;; 10% platform fee
(define-data-var min-challenge-reward uint u1000) ;; Minimum reward in microSTX
(define-data-var voting-period uint u1440) ;; Voting period in blocks (~10 days)

;; Challenge Status Constants
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_VOTING u2)
(define-constant STATUS_COMPLETED u3)
(define-constant STATUS_EXPIRED u4)

;; Data Maps
(define-map challenges 
    { challenge-id: uint }
    {
        researcher: principal,
        title: (string-ascii 128),
        description: (string-ascii 512),
        category: (string-ascii 64),
        reward-amount: uint,
        submission-deadline: uint,
        voting-deadline: uint,
        status: uint,
        solution-count: uint,
        winning-solution-id: (optional uint),
        created-at: uint
    }
)

(define-map solutions 
    { solution-id: uint }
    {
        challenge-id: uint,
        researcher: principal,
        title: (string-ascii 128),
        description: (string-ascii 1024),
        methodology: (string-ascii 512),
        results: (string-ascii 512),
        data-hash: (buff 32),
        vote-count: uint,
        submitted-at: uint
    }
)

(define-map votes
    { solution-id: uint, voter: principal }
    { 
        vote-weight: uint,
        voted-at: uint 
    }
)

(define-map researcher-profiles
    { researcher: principal }
    {
        name: (string-ascii 64),
        institution: (string-ascii 128),
        specialization: (string-ascii 128),
        reputation-score: uint,
        challenges-posted: uint,
        solutions-submitted: uint,
        challenges-won: uint
    }
)

(define-map peer-reviews
    { solution-id: uint, reviewer: principal }
    {
        score: uint,
        feedback: (string-ascii 256),
        reviewed-at: uint
    }
)

;; Public Functions

;; Create researcher profile
(define-public (create-profile 
    (name (string-ascii 64))
    (institution (string-ascii 128))
    (specialization (string-ascii 128)))
    (begin
        (asserts! (> (len name) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len institution) u0) ERR_INVALID_PARAMETERS)
        
        (map-set researcher-profiles { researcher: tx-sender }
            {
                name: name,
                institution: institution,
                specialization: specialization,
                reputation-score: u0,
                challenges-posted: u0,
                solutions-submitted: u0,
                challenges-won: u0
            }
        )
        (ok true)
    )
)

;; Post a new research challenge
(define-public (post-challenge
    (title (string-ascii 128))
    (description (string-ascii 512))
    (category (string-ascii 64))
    (reward-amount uint)
    (submission-period uint))
    (let 
        (
            (new-challenge-id (+ (var-get challenge-counter) u1))
            (submission-deadline (+ burn-block-height submission-period))
            (voting-deadline (+ submission-deadline (var-get voting-period)))
        )
        (asserts! (> (len title) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len description) u0) ERR_INVALID_PARAMETERS)
        (asserts! (>= reward-amount (var-get min-challenge-reward)) ERR_INVALID_PARAMETERS)
        (asserts! (>= (stx-get-balance tx-sender) reward-amount) ERR_INSUFFICIENT_PAYMENT)
        
        ;; Transfer reward to contract
        (try! (stx-transfer? reward-amount tx-sender (as-contract tx-sender)))
        
        (map-set challenges { challenge-id: new-challenge-id }
            {
                researcher: tx-sender,
                title: title,
                description: description,
                category: category,
                reward-amount: reward-amount,
                submission-deadline: submission-deadline,
                voting-deadline: voting-deadline,
                status: STATUS_ACTIVE,
                solution-count: u0,
                winning-solution-id: none,
                created-at: burn-block-height
            }
        )
        
        ;; Update researcher profile
        (match (map-get? researcher-profiles { researcher: tx-sender })
            profile (map-set researcher-profiles { researcher: tx-sender }
                (merge profile { challenges-posted: (+ (get challenges-posted profile) u1) }))
            false
        )
        
        (var-set challenge-counter new-challenge-id)
        (ok new-challenge-id)
    )
)

;; Submit a solution to a challenge
(define-public (submit-solution
    (challenge-id uint)
    (title (string-ascii 128))
    (description (string-ascii 1024))
    (methodology (string-ascii 512))
    (results (string-ascii 512))
    (data-hash (buff 32)))
    (let 
        (
            (challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR_CHALLENGE_NOT_FOUND))
            (new-solution-id (+ (var-get solution-counter) u1))
        )
        (asserts! (is-eq (get status challenge) STATUS_ACTIVE) ERR_INVALID_STATUS)
        (asserts! (<= burn-block-height (get submission-deadline challenge)) ERR_CHALLENGE_EXPIRED)
        (asserts! (> (len title) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len description) u0) ERR_INVALID_PARAMETERS)
        
        (map-set solutions { solution-id: new-solution-id }
            {
                challenge-id: challenge-id,
                researcher: tx-sender,
                title: title,
                description: description,
                methodology: methodology,
                results: results,
                data-hash: data-hash,
                vote-count: u0,
                submitted-at: burn-block-height
            }
        )
        
        ;; Update challenge solution count
        (map-set challenges { challenge-id: challenge-id }
            (merge challenge { solution-count: (+ (get solution-count challenge) u1) })
        )
        
        ;; Update researcher profile
        (match (map-get? researcher-profiles { researcher: tx-sender })
            profile (map-set researcher-profiles { researcher: tx-sender }
                (merge profile { solutions-submitted: (+ (get solutions-submitted profile) u1) }))
            false
        )
        
        (var-set solution-counter new-solution-id)
        (ok new-solution-id)
    )
)

;; Start voting phase for a challenge
(define-public (start-voting (challenge-id uint))
    (let 
        (
            (challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR_CHALLENGE_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender (get researcher challenge)) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status challenge) STATUS_ACTIVE) ERR_INVALID_STATUS)
        (asserts! (> burn-block-height (get submission-deadline challenge)) ERR_CHALLENGE_EXPIRED)
        (asserts! (> (get solution-count challenge) u0) ERR_INVALID_PARAMETERS)
        
        (map-set challenges { challenge-id: challenge-id }
            (merge challenge { status: STATUS_VOTING })
        )
        (ok true)
    )
)

;; Vote for a solution
(define-public (vote-solution 
    (solution-id uint)
    (vote-weight uint))
    (let 
        (
            (solution (unwrap! (map-get? solutions { solution-id: solution-id }) ERR_SOLUTION_NOT_FOUND))
            (challenge (unwrap! (map-get? challenges { challenge-id: (get challenge-id solution) }) ERR_CHALLENGE_NOT_FOUND))
        )
        (asserts! (is-eq (get status challenge) STATUS_VOTING) ERR_INVALID_STATUS)
        (asserts! (<= burn-block-height (get voting-deadline challenge)) ERR_CHALLENGE_EXPIRED)
        (asserts! (and (>= vote-weight u1) (<= vote-weight u5)) ERR_INVALID_PARAMETERS)
        (asserts! (is-none (map-get? votes { solution-id: solution-id, voter: tx-sender })) ERR_ALREADY_VOTED)
        
        (map-set votes 
            { solution-id: solution-id, voter: tx-sender }
            { vote-weight: vote-weight, voted-at: burn-block-height }
        )
        
        (map-set solutions { solution-id: solution-id }
            (merge solution { vote-count: (+ (get vote-count solution) vote-weight) })
        )
        (ok true)
    )
)

;; Finalize challenge and distribute rewards
(define-public (finalize-challenge (challenge-id uint) (winning-solution-id uint))
    (let 
        (
            (challenge (unwrap! (map-get? challenges { challenge-id: challenge-id }) ERR_CHALLENGE_NOT_FOUND))
            (winning-solution (unwrap! (map-get? solutions { solution-id: winning-solution-id }) ERR_SOLUTION_NOT_FOUND))
            (reward-amount (get reward-amount challenge))
            (platform-fee (/ (* reward-amount (var-get platform-fee-percentage)) u100))
            (winner-reward (- reward-amount platform-fee))
            (winner (get researcher winning-solution))
        )
        (asserts! (is-eq tx-sender (get researcher challenge)) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status challenge) STATUS_VOTING) ERR_INVALID_STATUS)
        (asserts! (> burn-block-height (get voting-deadline challenge)) ERR_CHALLENGE_EXPIRED)
        (asserts! (is-eq (get challenge-id winning-solution) challenge-id) ERR_INVALID_PARAMETERS)
        
        ;; Update challenge status
        (map-set challenges { challenge-id: challenge-id }
            (merge challenge { 
                status: STATUS_COMPLETED,
                winning-solution-id: (some winning-solution-id)
            })
        )
        
        ;; Transfer rewards
        (try! (as-contract (stx-transfer? winner-reward tx-sender winner)))
        (try! (as-contract (stx-transfer? platform-fee tx-sender CONTRACT_OWNER)))
        
        ;; Update winner's reputation
        (match (map-get? researcher-profiles { researcher: winner })
            profile (map-set researcher-profiles { researcher: winner }
                (merge profile { 
                    challenges-won: (+ (get challenges-won profile) u1),
                    reputation-score: (+ (get reputation-score profile) u10)
                }))
            false
        )
        
        (ok true)
    )
)

;; Submit peer review for a solution
(define-public (submit-review
    (solution-id uint)
    (score uint)
    (feedback (string-ascii 256)))
    (let 
        (
            (solution (unwrap! (map-get? solutions { solution-id: solution-id }) ERR_SOLUTION_NOT_FOUND))
            (challenge (unwrap! (map-get? challenges { challenge-id: (get challenge-id solution) }) ERR_CHALLENGE_NOT_FOUND))
        )
        (asserts! (is-eq (get status challenge) STATUS_VOTING) ERR_INVALID_STATUS)
        (asserts! (and (>= score u1) (<= score u10)) ERR_INVALID_PARAMETERS)
        (asserts! (not (is-eq tx-sender (get researcher solution))) ERR_UNAUTHORIZED)
        
        (map-set peer-reviews 
            { solution-id: solution-id, reviewer: tx-sender }
            {
                score: score,
                feedback: feedback,
                reviewed-at: burn-block-height
            }
        )
        (ok true)
    )
)

;; Read-only functions

(define-read-only (get-challenge (challenge-id uint))
    (map-get? challenges { challenge-id: challenge-id })
)

(define-read-only (get-solution (solution-id uint))
    (map-get? solutions { solution-id: solution-id })
)

(define-read-only (get-researcher-profile (researcher principal))
    (map-get? researcher-profiles { researcher: researcher })
)

(define-read-only (get-vote (solution-id uint) (voter principal))
    (map-get? votes { solution-id: solution-id, voter: voter })
)

(define-read-only (get-review (solution-id uint) (reviewer principal))
    (map-get? peer-reviews { solution-id: solution-id, reviewer: reviewer })
)

(define-read-only (get-challenge-counter)
    (var-get challenge-counter)
)

(define-read-only (get-solution-counter)
    (var-get solution-counter)
)

(define-read-only (get-platform-fee-percentage)
    (var-get platform-fee-percentage)
)

(define-read-only (get-min-challenge-reward)
    (var-get min-challenge-reward)
)

(define-read-only (get-voting-period)
    (var-get voting-period)
)

;; Admin functions (only contract owner)
(define-public (update-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= new-fee u25) ERR_INVALID_PARAMETERS) ;; Max 25% fee
        (var-set platform-fee-percentage new-fee)
        (ok true)
    )
)

(define-public (update-min-reward (new-min uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set min-challenge-reward new-min)
        (ok true)
    )
)

(define-public (update-voting-period (new-period uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> new-period u0) ERR_INVALID_PARAMETERS)
        (var-set voting-period new-period)
        (ok true)
    )
)

(define-public (withdraw-fees (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= amount (stx-get-balance (as-contract tx-sender))) ERR_INSUFFICIENT_PAYMENT)
        (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
        (ok true)
    )
)