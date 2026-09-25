-- ------ ** SECTION 5 : TABLE JOIN REGISTRANT & ELI_GRAD ** ------

-- =============================================================================
-- NOTE ON DATA REPRESENTATION: DATE OF BIRTH & AGE CALCULATIONS
-- =============================================================================
-- 1. DATA QUALITY BY CANDIDATE STATUS
--    * Admitted & Not Recommended: 
--      DOB is confirmed clean, full DD/MM/YYYY format (sourced from eligibility/graduation tables).
--    * No Show: 
--      Original DOB format is inconsistent/ambiguous (mixed D/M order, as documented in the registrant table). 
--      Only the birth YEAR is extracted and used.
-- 2. AGE CALCULATION IMPLICATIONS & LIMITATIONS
--    * Margin of Error: 
--      Any age calculation for No Show is therefore an ESTIMATE, with a possible margin of ±1 year 
--      due to the unresolved day/month ambiguity.
--    * Granularity Level: 
--      Age comparisons in this analysis are year-to-year only (e.g., birth year vs graduation/registration year). 
--      Since exact dates for graduation are not available either, this level of precision is sufficient 
--      for the analysis.

-- =============================================================================
-- ** PLANNING NOTES (thought process before execution) **
-- =============================================================================
-- Problem: registrant DOB format is ambiguous (mixed D/M order, documented
-- earlier), so it cannot be trusted for AGE calculation. However, DOB as a
-- raw STRING is still safe to use for MATCHING two rows as the same person —
-- string comparison doesn't require interpreting what the date actually means.
--
-- Also found: using composite key WITHOUT DOB (full_name + program_selected +
-- branch + phone_number) causes fan-out — e.g. "Participant 631" matches 12
-- different people in registrant with that same combination, distinguished
-- only by DOB. So DOB must stay in the key for the first matching pass.
--
-- IMPORTANT UPDATE: registrant_data was rebuilt (Section 1) to include
-- year_grad — the year a person's registration is expected to resolve into
-- (accounting for Oct-Dec submissions rolling into the next year). This
-- fixed 215 rows that were previously misclassified as duplicates when they
-- were actually valid re-registrations in different years. Because of this,
-- year_grad (registrant) / source_year (eligibility/graduation) MUST be
-- included as part of the matching key throughout Section 5 — otherwise the
-- same person registering in multiple years will incorrectly fan-out or
-- collapse into a single record.
--
-- PLANNED STEPS:
-- 1. JOIN registrant <-> clean_elig_grad_data using FULL composite key
--    (full_name + program_selected + branch + phone_number + date_of_birth
--    + year_grad = source_year). This is a high-precision match — 6 columns
--    must agree exactly.
-- 2. Rows that MATCH -> confirmed same person (and same year), kept as-is.
-- 3. Rows in clean_elig_grad_data with NO match -> saved separately as
--    "leftover_elig_grad" (people eligible/graduated but not confirmed
--    against registrant yet).
-- 4. Rows in registrant with NO match -> DOB is unreliable for these anyway,
--    so drop full DOB and extract YEAR only (birth_year). year_grad is KEPT
--    (not dropped) since it is reliable and needed to distinguish
--    re-registrations across different years.
-- 5. Remove duplicates again on this leftover registrant set, using
--    composite key WITH extracted birth_year AND year_grad (full_name +
--    program_selected + branch + phone_number + birth_year + year_grad) —
--    year_grad must stay in the key here, otherwise a person who registered
--    in multiple years would incorrectly collapse into one row again (the
--    same issue just fixed in Section 1).
-- 6. Try matching leftover registrant (deduplicated) against leftover_elig_grad
--    (from step 3), this time WITHOUT full DOB (since one side no longer has
--    it), but STILL WITH year_grad = source_year in the key — to avoid the
--    same fan-out problem seen with "Participant 631" in the first attempt.
-- 7. If matched -> merge/overwrite as confirmed same person.
--    If still unmatched ("leftover_elig_grad_2") -> these become candidate
--    "ghost students" (appear in eligibility/graduation but no trace in
--    registrant at all) -> to be added as new rows / flagged separately.
-- 8. Create new table as Prepared_data
-- =============================================================================


-- ** Step 1-2 : Match registrant to eligibility/graduation using full composite key
create table matched_registrant_elig as
select r.*, eg.eligibility_status, eg.admission_status, eg.final_grade, eg.graduation_status, eg.source_year
from clean_registrant_data r
join clean_elig_grad_data eg
    on r.full_name = eg.full_name
    and r.program_selected = eg.program_selected
    and r.branch = eg.branch
    and r.phone_number = eg.phone_number
    and r.date_of_birth = eg.date_of_birth
    and r.year_grad = eg.source_year;

-- Check how many rows matched
select COUNT(*) from matched_registrant_elig;
-- Result: 1671 rows


-- ** Step 3 leftover_elig_grad : Save leftover from clean_elig_grad_data (not yet confirmed against registrant)
create table leftover_elig_grad as
select eg.*
from clean_elig_grad_data eg
left join clean_registrant_data r
    on r.full_name = eg.full_name
    and r.program_selected = eg.program_selected
    and r.branch = eg.branch
    and r.phone_number = eg.phone_number
    and r.date_of_birth = eg.date_of_birth
    and r.year_grad = eg.source_year
where r.full_name is null;

select COUNT(*) from leftover_elig_grad;


-- ** Step 4 leftover_registrant : Save leftover from registrant (DOB will be simplified to year only)
create table leftover_registrant as
select r.*
from clean_registrant_data as r
left join clean_elig_grad_data as eg
    on r.full_name = eg.full_name
    and r.program_selected = eg.program_selected
    and r.branch = eg.branch
    and r.phone_number = eg.phone_number
    and r.date_of_birth = eg.date_of_birth
    and r.year_grad = eg.source_year
where eg.full_name is null;

-- Rows Check leftover_registrant:
select COUNT(*) from leftover_registrant;
-- Result: 1785 rows

-- Summary :
-- Step 1 (full key match + year_grad): 1671 rows matched -> matched_registrant_elig
-- Step 3 (leftover eligibility): 1194 rows, not yet confirmed -> leftover_elig_grad
-- Step 4 (leftover registrant): 1785 rows, not yet confirmed -> leftover_registrant
-- NOTE: leftovers are NOT "No Show" yet — some may just have DOB mismatch
-- or belong to a different registration year not yet reconciled.


-- ** Step 5: Extract birth_year, then remove duplicates on leftover_registrant
-- (birth_year replaces full DOB; year_grad is KEPT to avoid collapsing valid re-registrations across different years)

alter table leftover_registrant add column birth_year VARCHAR(4);

update leftover_registrant
set birth_year = SUBSTRING_INDEX(date_of_birth, '/', -1);

create table leftover_registrant_dedup as
with data_rank as (
    select *,
        row_number() over (
            partition by full_name, program_selected, branch, phone_number, birth_year, year_grad
            order by full_name
        ) as rn
    from leftover_registrant
)
select *
from data_rank
where rn = 1;

alter table leftover_registrant_dedup drop column rn;

-- Check how many rows remain after dedup
select
    (select COUNT(*) from leftover_registrant) as before_dedup,
    (select COUNT(*) from leftover_registrant_dedup) as after_dedup;


-- ** Step 6 : Try matching leftover_registrant_dedup to leftover_elig_grad WITHOUT full DOB, 
-- but STILL WITH year_grad = source_year (to avoid fan-out)
select rd.full_name, rd.branch, rd.program_selected, rd.phone_number, rd.birth_year, rd.year_grad,
       eg.full_name AS matched_elig_grad_name
from leftover_registrant_dedup rd
left join leftover_elig_grad eg
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
limit 20;

-- Count total matches
select COUNT(*) as matched_step6
from leftover_registrant_dedup rd
join leftover_elig_grad eg
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year;

-- Check for potential fan-out in Step 6
select rd.full_name, rd.program_selected, rd.branch, rd.phone_number, rd.year_grad, COUNT(*)
from leftover_registrant_dedup rd
join leftover_elig_grad eg
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
group by rd.full_name, rd.program_selected, rd.branch, rd.phone_number, rd.year_grad
having COUNT(*) > 1;

select full_name, date_of_birth, phone_number, admission_status, final_grade, graduation_status
from leftover_elig_grad
where full_name = 'Participant 24'
    and program_selected = 'Music - Drum'
    and branch = 'Jakarta'
    and phone_number = '85000000024'
    and source_year = '2016';
-- Result: 1 rows, DOB 1983

-- Random check 
select full_name, date_of_birth, phone_number, birth_year, year_grad, timestamp
from leftover_registrant_dedup
where full_name = 'Participant 24'
    and program_selected = 'Music - Drum'
    and branch = 'Jakarta'
    and phone_number = '85000000024'
    and year_grad = '2016';
-- Result: 3 rows, DOB inconsistent across submissions — 
	-- 1883 (implausible age), 
	-- 1983 (plausible, matches eligibility),
	-- 2020(impossible, birth year after registration year). Root cause: repeated
-- DOB entry errors by the registrant/admin, not a system/query issue. 


-- Count how many groups have fan-out (more than 1 match) vs total leftover_registrant_dedup
select COUNT(*) as total_groups_with_fanout
from (
    select rd.full_name, rd.program_selected, rd.branch, rd.phone_number, rd.year_grad
    from leftover_registrant_dedup rd
    join leftover_elig_grad eg
        on rd.full_name = eg.full_name
        and rd.program_selected = eg.program_selected
        and rd.branch = eg.branch
        and rd.phone_number = eg.phone_number
        and rd.year_grad = eg.source_year
    group by rd.full_name, rd.program_selected, rd.branch, rd.phone_number, rd.year_grad
    having COUNT(*) > 1
) as fanout_groups;
-- Result : 8 

-- Total rows in leftover_registrant_dedup
select COUNT(*) from leftover_registrant_dedup;
-- Result : 8 / 1769 


-- Check all 8 fan-out cases in registrant side
select full_name, date_of_birth, birth_year, year_grad, timestamp
from leftover_registrant_dedup
where full_name in (
    'Participant 24', 'Participant 1018', 'Participant 2825', 'Participant 1847',
    'Participant 2846', 'Participant 462', 'Participant 665', 'Participant 1501'
)
order by full_name, timestamp;
-- Result: DOB inconsistent across submissions for all 8 participants

-- Resolve DOB for fan-out cases using confirmed match from leftover_elig_grad (compare by year only)
select rd.full_name, rd.date_of_birth, rd.birth_year, rd.year_grad, rd.`timestamp`,
       eg.date_of_birth as eligibility_dob,
       SUBSTRING_INDEX(eg.date_of_birth, '/', -1) as eligibility_year,
       case
           when rd.birth_year = SUBSTRING_INDEX(eg.date_of_birth, '/', -1) then 'MATCH'
           else 'DISCARD'
       end as resolution_status
from leftover_registrant_dedup rd
join leftover_elig_grad eg
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
where rd.full_name in (
    'Participant 24', 'Participant 1018', 'Participant 2825', 'Participant 1847',
    'Participant 2846', 'Participant 462', 'Participant 665', 'Participant 1501'
)
order by rd.full_name, rd.`timestamp`;


-- Backup rows that will be deleted (safety net before DELETE)
create table leftover_registrant_dedup_discard_backup as
select rd.*
from leftover_registrant_dedup rd
join leftover_elig_grad eg
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
where rd.full_name in (
    'Participant 24', 'Participant 1018', 'Participant 2825', 'Participant 1847',
    'Participant 2846', 'Participant 462', 'Participant 665', 'Participant 1501'
)
and rd.birth_year <> SUBSTRING_INDEX(eg.date_of_birth, '/', -1);


-- Preview which rows will be deleted (birth_year vs eligibility_year)
select rd.full_name, rd.date_of_birth, rd.birth_year,
       SUBSTRING_INDEX(eg.date_of_birth, '/', -1) as eligibility_year,
       rd.`timestamp`
from leftover_registrant_dedup rd
join leftover_elig_grad eg
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
where rd.full_name in (
    'Participant 24', 'Participant 1018', 'Participant 2825', 'Participant 1847',
    'Participant 2846', 'Participant 462', 'Participant 665', 'Participant 1501'
)
and rd.birth_year <> SUBSTRING_INDEX(eg.date_of_birth, '/', -1)
order by rd.full_name, rd.`timestamp`;
-- Result: 9 rows (the incorrect DOB submissions for these 8 participants)


-- Delete the confirmed incorrect rows
delete rd
from leftover_registrant_dedup rd
join leftover_elig_grad eg
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
where rd.full_name in (
    'Participant 24', 'Participant 1018', 'Participant 2825', 'Participant 1847',
    'Participant 2846', 'Participant 462', 'Participant 665', 'Participant 1501'
)
and rd.birth_year <> SUBSTRING_INDEX(eg.date_of_birth, '/', -1);


-- Verify only 1 row per participant remains
select full_name, birth_year, COUNT(*)
from leftover_registrant_dedup
where full_name in (
    'Participant 24', 'Participant 1018', 'Participant 2825', 'Participant 1847',
    'Participant 2846', 'Participant 462', 'Participant 665', 'Participant 1501'
)
group by full_name, birth_year;


select COUNT(*) from leftover_registrant_dedup;
-- Result: 1760 (1769 - 9). 
-- Confirms only the 9 incorrect DOB rows were removed; all other rows untouched.

select * from leftover_registrant_dedup;

-- Re-check for any remaining fan-out across the FULL leftover_registrant_dedup
select rd.full_name, rd.program_selected, rd.branch, rd.phone_number, rd.year_grad, COUNT(*)
from leftover_registrant_dedup rd
join leftover_elig_grad eg
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
group by rd.full_name, rd.program_selected, rd.branch, rd.phone_number, rd.year_grad
having COUNT(*) > 1;
-- Result: 0 rows — no fan-out remaining anywhere in the dataset

-- final check, after fan-out fix: match leftover_registrant_dedup to leftover_elig_grad
select COUNT(*) as matched_step_final
from leftover_registrant_dedup rd
join leftover_elig_grad eg
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year;
-- Result : 1086 

-- Count unmatched from registrant side (final No Show candidates)
select COUNT(*) as unmatched_registrant_final
from leftover_registrant_dedup rd
left join leftover_elig_grad eg
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
where eg.full_name is null;
-- Result : 674 

-- Count unmatched from eligibility side (final ghost candidates)
select COUNT(*) as unmatched_elig_grad_final
from leftover_elig_grad eg
left join leftover_registrant_dedup rd
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
where rd.full_name is null;
-- Result : 108


select COUNT(distinct eg.full_name) as truly_unmatched
from leftover_elig_grad eg
left join leftover_registrant_dedup rd
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
where rd.full_name is null;
-- Result: 0 — confirms all 108 unmatched eligibility rows still have NULL
-- full_name, consistent with the known empty-identity anomaly. 
-- No new "ghost students" found.


-- Step 8 : Create New Table Prepared Data 
create table prepared_data as
		-- Part 1: Matched, full key incl. DOB + year_grad
select 
    r.full_name, r.nickname, r.gender, eg.date_of_birth, r.phone_number,
    r.institution_type, r.program_selected, r.branch,
    eg.checklist_a, eg.checklist_b, eg.checklist_c, eg.checklist_d, eg.checklist_e,
    eg.eligibility_status,
    eg.admission_status,
    eg.final_grade, eg.graduation_status,
    eg.source_year as year
from matched_registrant_elig r
join clean_elig_grad_data eg
    on r.full_name = eg.full_name
    and r.program_selected = eg.program_selected
    and r.branch = eg.branch
    and r.phone_number = eg.phone_number
    and r.year_grad = eg.source_year
   	and r.date_of_birth = eg.date_of_birth
union all
		-- Part 2: Matched, no DOB (fan-out resolved), WITH year_grad
select 
    rd.full_name, rd.nickname, rd.gender, eg.date_of_birth, rd.phone_number,
    rd.institution_type, rd.program_selected, rd.branch,
    eg.checklist_a, eg.checklist_b, eg.checklist_c, eg.checklist_d, eg.checklist_e,
    eg.eligibility_status,
    eg.admission_status,
    eg.final_grade, eg.graduation_status,
    eg.source_year as year
from leftover_registrant_dedup rd
join leftover_elig_grad eg
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
union all
		-- Part 3: No Show — use registrant's own year_grad (no eligibility year available)
select 
    rd.full_name, rd.nickname, rd.gender, rd.birth_year as date_of_birth, rd.phone_number,
    rd.institution_type, rd.program_selected, rd.branch,
    null, null, null, null, null,
    null as eligibility_status,
    'No Show' as admission_status,
    null as final_grade, null as graduation_status,
    rd.year_grad as year
from leftover_registrant_dedup rd
left join leftover_elig_grad eg
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
where eg.full_name is null
union all
		-- Part 4: 108 empty-identity rows — use eligibility's source_year
select 
    eg.full_name, null, eg.gender, eg.date_of_birth, eg.phone_number,
    null, eg.program_selected, eg.branch,
    eg.checklist_a, eg.checklist_b, eg.checklist_c, eg.checklist_d, eg.checklist_e,
    eg.eligibility_status,
    eg.admission_status,
    eg.final_grade, eg.graduation_status,
    eg.source_year as year
from leftover_elig_grad eg
left join leftover_registrant_dedup rd
    on rd.full_name = eg.full_name
    and rd.program_selected = eg.program_selected
    and rd.branch = eg.branch
    and rd.phone_number = eg.phone_number
    and rd.year_grad = eg.source_year
where rd.full_name is null;

-- Verify total count
select COUNT(*) from Prepared_data;
-- Expected: 1671 + 1086 + 674 + 108 = 3539
-- Result : 3539

select * from Prepared_data;

ALTER TABLE Prepared_data ORDER BY year ASC;
-- Decision (Section 1): 29/02/2019 (Participant 2131) kept as NULL for
-- year_grad. Cross-checked against clean_elig_grad_data — no match found.
-- No reliable source to determine correct date/year.




-- =============================================================================
-- SECTION 5 SUMMARY: FINAL JOIN — REGISTRANT + ELIGIBILITY/GRADUATION
-- =============================================================================
-- 1. Multi-Pass Reconciliation Pipeline
--    - Pass 1 (full composite key, incl. DOB + year_grad): 1,671 rows
--      matched between registrant and eligibility/graduation data with full
--      precision (6-column key, exact match).
--    - Pass 2 (fallback key, DOB dropped, year_grad retained):
--      leftover_registrant simplified to birth_year and deduplicated down
--      to 1,769 rows. Matching against leftover_elig_grad found an
--      additional 1,086 confirmed rows (post fan-out resolution) that
--      failed to match in Pass 1 due to DOB day/month inconsistency at
--      registration.

-- 2. Fan-Out Root-Cause Discovery & Purge (8 Participants / 9 Rows)
--    - Identified 8 participant groups (incl. Participant 24) causing row
--      fan-out in Pass 2.
--    - Root cause: repeated flawed DOB entries at registration (e.g. birth
--      years 1883 and 2020 submitted alongside a valid 1983 entry).
--    - Purged 9 corrupted DOB rows from leftover_registrant_dedup (backed
--      up in leftover_registrant_dedup_discard_backup beforehand). Fan-out
--      confirmed at 0 rows after cleanup.

-- 3. Ghost Student Audit & No Show Classification
--    - Reverse join on remaining eligibility data returned 108 unmatched
--      rows — all confirmed as the known full_name IS NULL anomaly
--      (Section 2). No new ghost students found (0).
--    - Isolated 674 registrant rows as valid No Show candidates
--      (registered but never proceeded to eligibility/admission).

-- 4. Final Master Table Breakdown (prepared_data)
--    Part 1 : Matched, Pass 1 (full key)                  = 1,671
--    Part 2 : Matched, Pass 2 (fallback key, fan-out fixed) = 1,086
--    Part 3 : Unmatched registrant (confirmed No Show)      = 674
--    Part 4 : Unmatched eligibility (blank identity, 2018)  = 108
--    TOTAL   : prepared_data                                = 3,539
--    (100% reconciled against source counts)
-- =============================================================================


---- INI DI CEK LAGI ---------

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



select count(*)
from (
    select r.full_name, r.program_selected, r.branch, r.phone_number, r.year_grad
    from matched_registrant_elig r
    join clean_elig_grad_data eg
        on r.full_name = eg.full_name
        and r.program_selected = eg.program_selected
        and r.branch = eg.branch
        and r.phone_number = eg.phone_number
        and r.year_grad = eg.source_year
) as part1_check;


select year, count(*) as total_rows
from prepared_data
group by year
order by year asc;

select program_selected, count(*) as total_rows
from prepared_data
group by program_selected
order by total_rows desc;


select full_name, program_selected, branch, year, final_grade, graduation_status
from prepared_data
where year = '2020';


select full_name, admission_status, year
from prepared_data
where year = '2020';


-- Chart utama (2015-2019 saja)
select year, count(*) as total_rows
from prepared_data
where year between '2015' and '2019'
group by year
order by year asc;

-- Baris terpisah untuk catatan
select 
    sum(case when year = '2020' then 1 else 0 end) as year_2020,
    sum(case when year is null then 1 else 0 end) as year_null
from prepared_data;

-- Breakdown :
select 
    year,
    case
        when admission_status = 'No Show' then 'No Show'
        when admission_status = 'Not Recommended' then 'Not Recommended'
        when admission_status = 'Admitted' then 'Passed'
        else 'Lainnya'
    end as outcome_category,
    count(*) as total
from prepared_data
where year between '2015' and '2019'
group by year, outcome_category
order by year asc, outcome_category asc;

-- 2019 Check
select year, admission_status, graduation_status, count(*) as total
from prepared_data
where year = '2019' and admission_status = 'Not Recommended'
group by year, admission_status, graduation_status;


-- Program_selected check count 
select sum(cnt) from (
  select program_selected, count(*) as cnt
  from prepared_data group by program_selected
) t;

-- program selected count grup by year
select 
    program_selected,
    sum(case when year = '2015' then 1 else 0 end) as "2015",
    sum(case when year = '2016' then 1 else 0 end) as "2016",
    sum(case when year = '2017' then 1 else 0 end) as "2017",
    sum(case when year = '2018' then 1 else 0 end) as "2018",
    sum(case when year = '2019' then 1 else 0 end) as "2019",
    count(*) as total
from prepared_data
where year between '2015' and '2019'
group by program_selected
order by total desc;

select COUNT(distinct branch) from prepared_data;
select distinct branch from prepared_data;
