-- =============================================================================
-- SECTION 4 : CROSS-TABLE (ELIGIBILITY <-> GRADUATION)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- [PLAN] Data Representation & Structural Strategy
-- -----------------------------------------------------------------------------
-- 1. Admission Status Consistency Verification
--    Cross-check admission_status between clean_eligibility_data (e) and
--    clean_graduation_data (g) to confirm values stayed uniform after
--    cleaning in Section 2 & 3.
--
-- 2. Join Key Integrity & Mismatch Isolation (Composite Key Strategy)
--    Issue    : Legacy system has no unique ID (student_id/registration_id).
--    Strategy : Build a composite natural key from 5 identity attributes
--               (full_name, program_selected, branch, date_of_birth,
--               phone_number) to avoid false matches or Cartesian-product
--               row duplication.
--    Hypothesis: Eligibility records with no Graduation match
--               (g.source_year IS NULL) are isolated and investigated per
--               source_year batch, so batch-specific patterns aren't
--               distorted by mixing years.
--
-- 3. Reverse Join Audit (Graduation -> Eligibility)
--    Run both Forward and Reverse joins between Graduation and Eligibility
--    to detect participants appearing directly in Graduation with no prior
--    registration/eligibility record (possible bypass of the intake
--    process, or lost/missing registration data).

-- -----------------------------------------------------------------------------
-- [PROBLEM STATEMENTS & INVESTIGATIVE LOGIC]
-- -----------------------------------------------------------------------------
-- 1. Historical Data Contradiction Investigation (Not Recommended vs Passed)
--    Investigate logical inconsistencies between admission status and
--    final graduation outcome in certain historical batches, checking at
--    raw row level whether it's a JOIN duplication artifact (Cartesian
--    product) or a genuine legacy data contradiction.
--
-- 2. Missing Graduation Outcomes Handling (NULL Records Strategy)
--    Problem : Some participants have an Eligibility record but no
--              final_grade/graduation_status in Graduation.
--    Policy  : If grade distribution in that batch varies (A-D), these
--              rows must NOT be defaulted to D/FAILED without evidence.
--              Keep as NULL — useful as an operational insight for
--              management (possible No Show / cancelled batch indicator).
--
-- 3. Investigation Strategy for Unmatched Records (Root-Cause Isolation)
--    Problem  : Some participants fail to match in Forward and/or Reverse
--               join.
--    Pipeline : Compare name lists from both join directions via CTE; test
--               elimination one-by-one on composite key fields (branch,
--               program_selected, phone_number, date_of_birth) to isolate
--               which attribute is causing the JOIN failure.
--    Action   : If mismatch is due to a missing value (NULL) in one
--               reference table, backfill it from the paired table before
--               materializing the final consolidated table.

-- -----------------------------------------------------------------------------
-- [EXECUTION STEPS]
-- -----------------------------------------------------------------------------
-- STEP 1 : Consistency Audit
--          Check admission_status consistency and source_year alignment.
--
-- STEP 2 : Year-by-Year Investigation
--          Analyze g.source_year IS NULL patterns per year batch.
--
-- STEP 3 : Mismatch Root-Cause Analysis
--          Identify unmatched entries in both directions; isolate the
--          column causing JOIN failure via variable testing.
--
-- STEP 4 : Data Restoration (Backfill)
--          Run UPDATE with JOIN to fill missing data from the reference
--          table where valid.
--
-- STEP 5 : Master Consolidation Table Creation
--          Materialize clean_elig_grad_data; reconcile total row counts.
-- =============================================================================

-- Verify admission_status CONSISTENCY BEFORE JOIN
with temp as (
select e.full_name, e.admission_status as addm_eli, 
       g.admission_status as addm_grad,
       e.source_year 
from clean_eligibility_data as e
left join clean_graduation_data as g
    on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
where e.admission_status <> g.admission_status)
select distinct addm_eli, addm_grad
from temp;
-- Result: 0 rows — admission_status now fully consistent between both tables


-- Verify : check whether eli_source_year and grad_source_year are always the same
select e.source_year as eli_year, g.source_year as grad_year, COUNT(*)
from clean_eligibility_data as e
left join clean_graduation_data as g
	 on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number 
group by e.source_year, g.source_year;
-- Result: 2015, 2018, 2019 have NULL grad_year — some data missing in graduation


select e.source_year as eli_year, g.source_year as grad_year, COUNT(*)
from clean_eligibility_data as e
inner join clean_graduation_data as g
	 on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number 
group by e.source_year, g.source_year;


-- Check reverse direction: anyone in graduation but NOT in eligibility
select g.full_name, g.branch, g.program_selected, g.source_year
from clean_graduation_data g
left join  clean_eligibility_data e
    on g.full_name = e.full_name
    and g.program_selected = e.program_selected
    and g.branch = e.branch
    and g.date_of_birth = e.date_of_birth
    and g.phone_number = e.phone_number
where e.full_name is null;
-- Result: 5 people found, all from 2019 — to be checked further

-- Check the NULL data found earlier in graduation source_year (2015, 2018, 2019)
select distinct e.admission_status, g.final_grade, g.graduation_status, e.source_year as eli_year
from clean_eligibility_data as e
left join clean_graduation_data as g
 on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
where g.source_year is null;
-- Result: too mixed/random to draw a pattern from combined years — better check year by year


-- Check only year 2015
select distinct e.admission_status, g.final_grade, g.graduation_status, e.source_year as eli_year
from clean_eligibility_data as e
left join clean_graduation_data as g
 on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
where e.source_year = '2015' and g.source_year is not null;
-- Result :
	-- 1. Source data only records passing students (all rows are 'PASSED').
select count(*)
from clean_eligibility_data e
left join clean_graduation_data g
    on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
where e.source_year = '2015' and g.source_year is null;
-- Result: 34 rows — completes the unmatched-outcome picture across all 3 years

select e.full_name, e.admission_status, g.final_grade, g.graduation_status
from clean_eligibility_data e
left join clean_graduation_data g
    on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
where e.source_year = '2015' 
    and e.admission_status = 'Not Recommended' 
    and g.final_grade = 'A';
-- Result: 3 rows — "Not Recommended" in eligibility but "A"/PASSED in graduation.
-- Anomaly found, cause not yet verified.

-- Randomly check one of the 3 people directly in eligibility & graduation
select *
from clean_eligibility_data
where full_name = 'Participant 2431';

select *
from clean_graduation_data
where full_name = 'Participant 2431';
-- Confirmed genuine contradiction (not a join error). Flagged as known anomaly.

-- Check "Not Recommended but Passed" cases in other years
select e.source_year, COUNT(*) AS not_recommended_but_passed
from clean_eligibility_data e
join clean_graduation_data g
    on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
where e.admission_status = 'Not Recommended'
    and g.graduation_status = 'PASSED'
group by e.source_year;
-- Result: no other years found — this anomaly only occurs in 2015 (3 cases)


-- Continue checking NULL rows in 2018
select distinct e.admission_status, g.final_grade, g.graduation_status, e.source_year as eli_year
from clean_eligibility_data as e
left join clean_graduation_data as g
 on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
where e.source_year = '2018' and g.source_year is not null;
-- Result: Not Recommended pairs with D/FAILED, makes sense. 
-- Grades spread A-D, so unlike 2015, NULL rows here can't be assumed as all D/FAILED.

select e.full_name, e.admission_status, g.final_grade, g.graduation_status, e.source_year as eli_year
from clean_eligibility_data as e
left join clean_graduation_data as g
 on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
where e.source_year = '2018' and g.source_year is null;
-- Result: 108 rows — admission_status filled but no final_grade/graduation_status.
-- No way to determine the actual outcome from available data.
-- Kept as-is (NULL), to be used as an insight for admin & management.

-- Check only year 2019
select distinct e.admission_status, g.final_grade, g.graduation_status, e.source_year as eli_year
from clean_eligibility_data as e
left join clean_graduation_data as g
 on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
where e.source_year = '2019' and g.source_year is not null;
-- Result: Not Recommended pairs with D/FAILED, makes sense. 
-- Grades spread A-D, so unlike 2015, NULL rows here can't be assumed as all D/FAILED.

select e.full_name, e.admission_status, g.final_grade, g.graduation_status, e.source_year as eli_year
from clean_eligibility_data as e
left join clean_graduation_data as g
 on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
where e.source_year = '2019' and g.source_year is null;
-- Result: same pattern as 2018 — admission_status filled, but no final_grade or graduation_status recorded. 
-- Kept as-is (NULL), same treatment as 2018.
-- 5 rows recorded
-- (34 in 2015 + 108 in 2018 + 5 in 2019 = 147 total pre-backfill)


-- Check the 5 people in graduation 2019 with no matching eligibility record
select g.full_name, g.branch, g.program_selected, g.date_of_birth, g.phone_number, 
       g.final_grade, g.graduation_status, g.source_year
from clean_graduation_data g
left join clean_eligibility_data e
    on g.full_name = e.full_name
    and g.program_selected = e.program_selected
    and g.branch = e.branch
    and g.date_of_birth = e.date_of_birth
    and g.phone_number = e.phone_number
where e.full_name is null
    and g.source_year = '2019';
-- Result: looks like the same 5 names as the earlier forward check — 
-- worth to verify if these are indeed the same people.

-- Check if the 5 reverse-matched names overlap with the forward-unmatched names
-- CTE Identify graduation records that do not have matching eligibility records
with 
grad as (
    select g.full_name, g.source_year
    from clean_graduation_data as g
    left join clean_eligibility_data as e
        on g.full_name = e.full_name
        and g.program_selected = e.program_selected
        and g.branch = e.branch
        and g.date_of_birth = e.date_of_birth
        and g.phone_number = e.phone_number
    where e.full_name is null
),
-- CTE Identify eligibility records that do not have matching graduation records
elig as (
    select e.full_name
    from clean_eligibility_data as e
    left join clean_graduation_data as g
        on e.full_name = g.full_name
        and e.program_selected = g.program_selected
        and e.branch = g.branch
        and e.date_of_birth = g.date_of_birth
        and e.phone_number = g.phone_number
    where g.full_name is null
)
-- Find names in both tables that failed to join due to typos/mismatched data
select full_name
from grad
where source_year = '2019'
  and full_name in (select full_name from elig);
-- Result: confirmed — same 5 people appear in both unmatched sets. 
-- This means they exist in both tables, but fail to match due to a mismatch in one of program_selected,
-- date_of_birth, or phone_number (branch already ruled out).


-- program_selected check
with check2019 as (
select e.full_name, e.program_selected as eli_prog, g.program_selected as grad_prog,
    case 
        when e.program_selected = g.program_selected then 'Match'
        when g.program_selected is null then 'Not Found'
        else 'Mismatch'
    end as notes
from clean_eligibility_data as e
left join clean_graduation_data as g
    on e.full_name = g.full_name
where e.source_year = '2019' 
    and e.full_name in (
        'Participant 2325',
        'Participant 2326',
        'Participant 2330',
        'Participant 2331',
        'Participant 2336'
    ))
select distinct notes
from check2019;
-- Result: Match — so program_selected is not the cause

-- date_of_birth check
with check2019 as (
select e.full_name, e.date_of_birth as eli_dob, g.date_of_birth as grad_dob,
    case when e.date_of_birth = g.date_of_birth then 'Match'
         when g.date_of_birth is null then 'Not Found in Graduation'
         else 'Mismatch'
    end as notes
from clean_eligibility_data as e
left join clean_graduation_data as g
    on e.full_name = g.full_name
where e.source_year = '2019' 
    and e.full_name in (
        'Participant 2325','Participant 2326','Participant 2330',
        'Participant 2331','Participant 2336'))
select distinct notes from check2019;
-- Result: Mismatch — this is the cause of the failed join
-- program_selected and phone_number were tested the same way beforehand
-- and both returned Match — ruled out as the failing field.


-- phone number check
with check2019 as (
select e.full_name, e.phone_number as eli_pn, g.phone_number as grad_pn,
    case 
        when e.phone_number = g.phone_number then 'Match'
        when g.phone_number is null then 'Not Found in Graduation'
        else 'Mismatch'
    end as notes
from clean_eligibility_data as e
left join clean_graduation_data as g
    on e.full_name = g.full_name
where e.source_year = '2019' 
    and e.full_name in (
        'Participant 2325',
        'Participant 2326',
        'Participant 2330',
        'Participant 2331',
        'Participant 2336'
    ))
select distinct notes
from check2019;
-- Result: Match — phone_number is fine
-- CONFIRMED: date_of_birth is the cause of the mismatch

select e.full_name, e.date_of_birth as eli_dob, g.date_of_birth as grad_dob,
    case 
        when e.date_of_birth = g.date_of_birth then 'Match'
        when g.date_of_birth is null then 'Not Found in Graduation'
        else 'Mismatch'
    end as notes
from clean_eligibility_data as e
left join clean_graduation_data as g
    on e.full_name = g.full_name
where e.source_year = '2019' 
    and e.full_name in (
        'Participant 2325',
        'Participant 2326',
        'Participant 2330',
        'Participant 2331',
        'Participant 2336'
    );
-- Result: date_of_birth is NULL in eligibility, but present in graduation.
-- This means the missing DOB in eligibility could be filled in using the DOB from graduation as a reference.

-- Update dob for eligibility_data
update clean_eligibility_data as e
join clean_graduation_data as g
	on e.full_name = g.full_name
	and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.phone_number = g.phone_number
set e.date_of_birth = g.date_of_birth
where e.date_of_birth is null and e.full_name in(
	'Participant 2325', 'Participant 2326', 'Participant 2330',
    'Participant 2331', 'Participant 2336');

-- Verify : check data update
select full_name, date_of_birth
from clean_eligibility_data
where full_name in (
	'Participant 2325', 'Participant 2326', 'Participant 2330',
    'Participant 2331', 'Participant 2336');
-- Result : updated

-- Create Table 'clean_elig_grad_data'
create table clean_elig_grad_data as
select 
    e.full_name, e.nickname, e.gender, e.date_of_birth, e.phone_number,
    e.program_selected,e.branch,
    e.checklist_a,
    e.checklist_b,
    e.checklist_c,
    e.checklist_d,
    e.checklist_e,
    case 
        when e.checklist_a is null or e.checklist_b is null or e.checklist_c is null 
        	or e.checklist_d is null or e.checklist_e is null then null
        WHEN e.checklist_a = 'Not Completed' or e.checklist_b = 'Not Completed' 
        	or e.checklist_c = 'Not Completed' or e.checklist_d = 'Not Completed' 
        	or e.checklist_e = 'Not Completed' then 'Not Eligible'
        else 'Eligible'
    end as eligibility_status,
    e.admission_status,
    g.final_grade,
    g.graduation_status,
    e.source_year
from clean_eligibility_data as e
left join clean_graduation_data as g
    on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number;

-- Verify clean_elig_grad_data
select *
from clean_elig_grad_data;

-- Count check
select
    (select COUNT(*) from clean_eligibility_data) as eligibility_count,
    (select COUNT(*) from clean_elig_grad_data) as join_elig_grad_count;
-- Result: Match (2865 = 2865)

select g.full_name, g.branch, g.program_selected, g.date_of_birth, g.phone_number, count(*)
from clean_eligibility_data e
join clean_graduation_data g
    on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
group by g.full_name, g.branch, g.program_selected, g.date_of_birth, g.phone_number
having count(*) > 1;

select count(*)
from clean_eligibility_data e
left join clean_graduation_data g
    on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
where e.source_year = '2015' and g.source_year is null;

--- ini perlu di cek dulu --- karena ini tambahan :
select count(*) as final_matched
from clean_eligibility_data e
join clean_graduation_data g
    on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number;

select count(*) as matched_excluding_backfilled_5
from clean_eligibility_data e
join clean_graduation_data g
    on e.full_name = g.full_name
    and e.program_selected = g.program_selected
    and e.branch = g.branch
    and e.date_of_birth = g.date_of_birth
    and e.phone_number = g.phone_number
where e.full_name not in (
    'Participant 2325','Participant 2326','Participant 2330',
    'Participant 2331','Participant 2336'
);

-- =============================================================================
-- SECTION 4 : SUMMARY (ELIGIBILITY <-> GRADUATION)
-- =============================================================================

-- 1. Consistency Audit & Historical Anomaly (Batch 2015)
--    - Cross-table check: 0 conflicting rows. admission_status between
--      clean_eligibility_data and clean_graduation_data confirmed 100%
--      consistent post-cleaning.
--    - Legacy contradiction: 3 unique cases in batch 2015 (incl.
--      Participant 2431) with admission_status = 'Not Recommended' in
--      Eligibility, but final_grade = 'A' / graduation_status = 'PASSED'
--      in Graduation.
--      - Raw-row verification confirmed this is NOT a JOIN duplication
--        artifact (Cartesian product) — a genuine legacy data
--        contradiction.
--      - Cross-year check: anomaly confirmed isolated to batch 2015 only
--        (0 cases in 2016-2019).

-- 2. Unmatched & Missing Outcomes (2018 & 2019)
--    - 108 rows (2018) and 5 rows (2019) have an Eligibility admission
--      record but no matching grade/graduation_status in Graduation
--      (g.source_year IS NULL).
--    - Decision: since grade distribution in this period varies (A-D),
--      these rows are kept as NULL (not forced to D/FAILED) — used as an
--      operational insight for management to flag possible No Show /
--      cancelled-batch candidates.

-- 3. Mismatch Root-Cause Isolation & Data Restoration (Batch 2019)
--    - Forward & Reverse join cross-check isolated 5 unmatched
--      participants in batch 2019 (Participant 2325, 2326, 2330, 2331,
--      2336) — unmatched from both Eligibility and Graduation sides.
--    - Column elimination test result:
--      - program_selected : MATCH
--      - phone_number      : MATCH
--      - date_of_birth     : MISMATCH (NULL in Eligibility, fully
--        populated in Graduation).
--    - Backfilled date_of_birth for these 5 rows in clean_eligibility_data
--      using clean_graduation_data as reference. Post-update, all 5
--      participants matched successfully.

-- 4. Master Consolidation Table & Row Reconciliation
--    - clean_elig_grad_data materialized successfully.
--    - Row-count reconciliation: 2,865 rows in clean_elig_grad_data,
--      100% MATCH against the clean_eligibility_data reference table
--      (2,865 = 2,865).
-- =============================================================================

