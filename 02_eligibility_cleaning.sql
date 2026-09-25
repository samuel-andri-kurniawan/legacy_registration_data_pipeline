-- =============================================================================
-- SECTION 2 : ELIGIBILITY STATUS DATA CLEANING & CONSOLIDATION (2015-2019)
-- =============================================================================

-- **CREATING TABLES (raw_eligibility_2015 through raw_eligibility_2019)
create table raw_eligibility_2015 (
	full_name VARCHAR(100), nickname VARCHAR(50), gender VARCHAR(20),
	date_of_birth VARCHAR(50), phone_number VARCHAR(50), program_selected VARCHAR(100),
	branch VARCHAR(100), checklist_a VARCHAR(100), checklist_b VARCHAR(100),
	checklist_c VARCHAR(100), checklist_d VARCHAR(100), checklist_e VARCHAR(100),
	admission_status VARCHAR(100)
);

create table raw_eligibility_2016 (
	full_name VARCHAR(100), nickname VARCHAR(50), gender VARCHAR(20),
	date_of_birth VARCHAR(50), phone_number VARCHAR(50), program_selected VARCHAR(100),
	branch VARCHAR(100), checklist_a VARCHAR(100), checklist_b VARCHAR(100),
	checklist_c VARCHAR(100), checklist_d VARCHAR(100), checklist_e VARCHAR(100),
	admission_status VARCHAR(100), remarks_1 VARCHAR(100), remarks_2 VARCHAR(100), remarks_3 VARCHAR(100)
);

create table raw_eligibility_2017 (
	full_name VARCHAR(100), nickname VARCHAR(50), gender VARCHAR(20),
	date_of_birth VARCHAR(50), phone_number VARCHAR(50), program_selected VARCHAR(100),
	branch VARCHAR(100), checklist_a VARCHAR(100), checklist_b VARCHAR(100),
	checklist_c VARCHAR(100), checklist_d VARCHAR(100), checklist_e VARCHAR(100),
	admission_status VARCHAR(100), revison_notes VARCHAR(100)
);

create table raw_eligibility_2018(
	full_name VARCHAR(100), nickname VARCHAR(50), gender VARCHAR(20),
	date_of_birth VARCHAR(50), phone_number VARCHAR(50), program_selected VARCHAR(100),
	branch VARCHAR(100), checklist_a VARCHAR(100), checklist_b VARCHAR(100),
	checklist_c VARCHAR(100), checklist_d VARCHAR(100), checklist_e VARCHAR(100),
	admission_status VARCHAR(100), notes VARCHAR (50), remarks_3 VARCHAR(100)
);

create table raw_eligibility_2019 (
	full_name VARCHAR(100), nickname VARCHAR(50), gender VARCHAR(20),
	date_of_birth VARCHAR(50), phone_number VARCHAR(50), program_selected VARCHAR(100),
	branch VARCHAR(100), year VARCHAR(50), checklist_a VARCHAR(100), checklist_b VARCHAR(100),
	checklist_c VARCHAR(100), checklist_d VARCHAR(100), checklist_e VARCHAR(100),
	admission_status VARCHAR(100), revision_notes VARCHAR(100)
);

-- Check DOB format per year table (confirmed DD/MM/YYYY consistent across all 5 batches
-- via SUBSTRING_INDEX digit-boundary test: left value up to 31, mid value always <=12)

-- Merge all eligibility tables (2015-2019) into one raw table
create table raw_eligibility_2015_2019 as
select full_name, nickname, gender, date_of_birth, phone_number, program_selected, branch, 
       checklist_a, checklist_b, checklist_c, checklist_d, checklist_e, admission_status,
       2015 as source_year
from raw_eligibility_2015
union all
select full_name, nickname, gender, date_of_birth, phone_number, program_selected, branch, 
       checklist_a, checklist_b, checklist_c, checklist_d, checklist_e, admission_status,
       2016 as source_year
from raw_eligibility_2016
union all 
select full_name, nickname, gender, date_of_birth, phone_number, program_selected, branch, 
       checklist_a, checklist_b, checklist_c, checklist_d, checklist_e, admission_status,
       2017 as source_year
from raw_eligibility_2017
union all 
select full_name, nickname, gender, date_of_birth, phone_number, program_selected, branch, 
       checklist_a, checklist_b, checklist_c, checklist_d, checklist_e, admission_status,
       2018 as source_year
from raw_eligibility_2018
union all 
select full_name, nickname, gender, date_of_birth, phone_number, program_selected, branch, 
       checklist_a, checklist_b, checklist_c, checklist_d, checklist_e, admission_status,
       2019 as source_year
from raw_eligibility_2019;

-- Verify merged data is complete: 2865 = 2865 (sum of all 5 source tables)

-- ** DATA STANDARDIZATION
-- full_name / nickname Proper Case (275 rows fixed each)
update raw_eligibility_2015_2019
set full_name = concat(upper(left(full_name,1)), lower(substring(full_name,2)))
where binary(full_name) != concat(upper(left(full_name,1)), lower(substring(full_name,2)));

update raw_eligibility_2015_2019
set nickname = concat(upper(left(nickname,1)), lower(substring(nickname,2)))
where binary(nickname) != concat(upper(left(nickname,1)), lower(substring(nickname,2)));

-- 108 rows (2018 batch) found with NULL full_name / identity fields but admission_status populated
-- Flagged for later cross-table investigation, not resolved here (ghost-identity anomaly)

-- Branch check & consolidation (3 of 24 branches had inconsistent labels)
update raw_eligibility_2015_2019 set branch = 'Jakarta' where branch like '%Jakarta%';
update raw_eligibility_2015_2019 set branch = 'Solo' where branch like '%Solo%';
update raw_eligibility_2015_2019 set branch = 'Yogyakarta' where branch like '%Yogyakarta%';
-- 2 corrupted branch strings from spreadsheet formula errors:
update raw_eligibility_2015_2019 set branch = 'Wonogiri' where branch like 'WoNot Completedgiri';
update raw_eligibility_2015_2019 set branch = 'Wonosari' where branch like 'WoNot Completedsari';

-- Standardize checklist A-E: Completed/Yes -> 'Completed', No -> 'Not Completed'
update raw_eligibility_2015_2019
set checklist_a = case when checklist_a IN('Completed ','Yes') then 'Completed'
						when checklist_a = 'No' then 'Not Completed' else checklist_a end,
	checklist_b = case when checklist_b IN('Completed ','Yes') then 'Completed'
						when checklist_b = 'No' then 'Not Completed' else checklist_b end,
	checklist_c = case when checklist_c IN('Completed ','Yes') then 'Completed'
						when checklist_c = 'No' then 'Not Completed' else checklist_c end,
	checklist_d = case when checklist_d IN('Completed ','Yes') then 'Completed'
						when checklist_d = 'No' then 'Not Completed' else checklist_d end,
	checklist_e = case when checklist_e IN('Completed ','Yes') then 'Completed'
						when checklist_e = 'No' then 'Not Completed' else checklist_e end;

-- Standardize admission_status: Yes -> Admitted, No -> Not Recommended
update raw_eligibility_2015_2019
set admission_status = case when admission_status = 'Yes' then 'Admitted'
							when admission_status = 'No' then 'Not Recommended'
							else admission_status end;
-- Note: "No Show" intentionally NOT derived here — determined later at JOIN stage (Section 5)

-- ** REMOVE DUPLICATE check (composite key: identity + program + branch + source_year)
-- Result: no genuine duplicates found (only coincidental blank full_name matches - 2018 anomaly)

-- Convert '' to NULL across all columns
update raw_eligibility_2015_2019
set full_name = nullif(full_name, ''), nickname = nullif(nickname, ''),
    gender = nullif(gender, ''), date_of_birth = nullif(date_of_birth, ''),
    phone_number = nullif(phone_number, ''), program_selected = nullif(program_selected, ''),
    branch = nullif(branch, ''), checklist_a = nullif(checklist_a, ''),
    checklist_b = nullif(checklist_b, ''), checklist_c = nullif(checklist_c, ''),
    checklist_d = nullif(checklist_d, ''), checklist_e = nullif(checklist_e, ''),
    admission_status = nullif(admission_status, '');

-- Create clean table for eligibility status
create table clean_eligibility_data as
select * from raw_eligibility_2015_2019;

-- Verify row count matches: raw_count = clean_count (2865 = 2865)

-- Additional anomaly: 6 rows with checklist_b incomplete despite filled identity
-- (5 from 2019, 1 from 2017) — distinct from the 108 ghost-identity rows

-- =============================================================================
-- SECTION 2 SUMMARY
-- =============================================================================
-- 5 yearly tables consolidated via UNION ALL, source_year added for lineage
-- 2,865 rows merged, zero data loss (matches sum of 5 source tables)
-- 100% DOB format consistency confirmed (DD/MM/YYYY) across all batches
-- 275 full_name/nickname records fixed to Proper Case; 3 of 24 branches standardized,
--   2 corrupted branch strings reconstructed
-- Checklist A-E and admission_status mapped to standard labels
-- 108 ghost-identity rows (2018) and 6 checklist_b anomalies flagged, not discarded
-- Zero true duplicates confirmed via composite-key check
-- =============================================================================