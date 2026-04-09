# Admin Operating Guide

## System Overview

This system is designed to:
- distribute leads to staff
- track calling work properly
- identify positive leads
- manage callback commitments
- calculate earned salary fairly
- reduce fake or weak calling patterns

## Lead Management

### Main lead areas
- `Lead Management`
  For active lead handling and assignment
- `Follow-Up Queue`
  For positive leads marked as follow up
- `Call Back Tracker`
  For customer-requested callbacks with date and time
- `Rejected & No Response`
  For recovery handling and later review

### Lead status meaning
- `New`
  Fresh lead ready for staff calling
- `Follow Up`
  Positive lead found by staff
- `Call Back`
  Customer asked to be called later on a selected date and time
- `Rejected`
  Customer is not interested
- `No Response`
  Customer did not attend or the discussion did not happen properly
- `Converted`
  Final successful outcome

### Queue behavior
- Staff queue mainly shows:
  - `New`
  - due `Call Back`
- `Follow Up` does not return to the normal staff calling list
- `Rejected` and `No Response` are handled in the recovery area unless assigned back

### Manual allocation
- Admin can assign leads directly from lead editing
- Admin can also use bulk allocation on the lead page
- If the selected staff member is already full, lower-priority leads from the bottom are released first
- Then the newly selected leads are added

### Automatic allocation
- Automatic allocation uses active queue limits
- It fills staff queues fairly based on current load
- Due callbacks are prioritized when their selected date and time arrive

## Customer Call Flow

### Staff side result flow
- Staff starts the customer call
- After the call, the result is saved
- `Call Back` requires both date and time slot
- Invalid short calls are returned to queue handling
- A customer result must be completed before moving forward in the flow

### Quality control
- Weak calling patterns are reviewed
- Blocks with only unanswered attempts do not add payable work time
- Very poor real-call ratios are flagged for review
- Away history is visible for monitoring, but not treated as a score penalty by itself

## Work Hour Logic

### How work time is counted
- Work time is based on verified calling activity
- Continuous call work is grouped into calling blocks
- If there is more than `1 minute` without a new call, that work block stops
- After a connected calling block, up to `90 seconds` of cooldown is allowed
- Idle time after that is not counted

### Protection against weak calling patterns
- A block with only `0 second` calls gives `0` work time
- `Invalid Short` calls do not count for payable work time
- If a block has too many attempts with too few real conversations, only the real call activity is counted

## Salary System

### Salary components
- `Base Pay`
  Calculated from worked time
- `Call Earnings`
  Added if a call-based earning rate is configured
- `Bonus Earnings`
  Includes conversion bonus and hourly call bonus

### Pending salary
- Pending salary means earned amount that is not yet paid
- Paid amounts are deducted from the balance
- The same earned amount is not meant to be paid twice

### Weekly and monthly payout
- Weekly staff are prepared based on the selected weekly payout day
- Monthly staff are prepared on the last day of the month
- Advance can be released from the current running earned amount when available

## Hourly Call Bonus

### Current rule
- Bonus is checked fresh for each day
- Each completed work hour is checked separately
- A completed hour must cross the preset call target before bonus starts
- The next bonus block starts only after the next full work hour is completed
- Partial unfinished hours do not unlock the next bonus

### Example
- `1 completed hour` with target `50 calls`
  - `50 calls` = no bonus
  - `51 calls` = bonus for `1` extra call
- `2 completed hours`
  - bonus for the second hour starts only after the second full work hour is completed

## Salary Payment Workflow

### Salary overview
- Shows pending salary
- Shows advance availability
- Shows paid salary history
- Shows referral reward payments if enabled

### Open payment
- Admin opens the staff salary detail page
- Reviews:
  - earned amount
  - worked time
  - bonus
  - paid amount
  - balance
- Pays only the remaining balance or allowed advance

## Referral Program

### Referral flow
- Admin can enable or disable the referral program
- Staff can submit a referral when the program is active
- Referral progress can move through:
  - Not Joined
  - Joined
  - Started Working
  - Completed
- Reward becomes payable only after the required work condition is completed

## Admin Best Practice

- Review follow-up and callback pages daily
- Use recovery pages to reactivate the right leads
- Watch staff review notes for weak calling patterns
- Pay only from the salary detail page after checking the calculations
- Use manual allocation when urgent leads must go to specific staff

## Final note
The system works best when:
- lead statuses are used correctly
- callback dates are set carefully
- salary is paid only from earned balance
- weak calling patterns are reviewed early
