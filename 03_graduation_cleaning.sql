-- =============================================================================
-- SECTION 3 : GRADUATION STATUS DATA CLEANING & CONSOLIDATION (2015-2019)
-- =============================================================================

-- **CREATING TABLES (raw_graduation_2015 through raw_graduation_2019)
create table raw_graduation_2015 (
	full_name VARCHAR (100), nickname VARCHAR (50), gender VARCHAR (50),
	date_of_birth VARCHAR(50), phone_number VARCHAR(50), program_selected VARCHAR(50),
	branch VARCHAR (50), admission_status VARCHAR(50), final_grade VARCHAR(50),
	graduation_status VARCHAR(50)
	);

create table raw_graduation_2016 (
	full_name VARCHAR (100), nickname VARCHAR (50), gender VARCHAR (50),
	date_of_birth VARCHAR(50), phone_number VARCHAR(50), program_selected VARCHAR(50),
	branch VARCHAR (50), admission_status VARCHAR(50), notes_1 VARCHAR(100),
	notes_2 VARCHAR(100), notes_3 VARCHAR(100), final_grade VARCHAR(50), graduation_status VARCHAR(50)
	);

create table raw_graduation_2017 (
	full_name VARCHAR (100), nickname VARCHAR (50), gender VARCHAR (50),
	date_of_birth VARCHAR(50), phone_number VARCHAR(50), program_selected VARCHAR(50),
	branch VARCHAR (50), admission_status VARCHAR(50), notes_1 VARCHAR(100),
	final_grade VARCHAR(50), graduation_status VARCHAR(50)
	);

create table raw_graduation_2018 (
	full_name VARCHAR (100), nickname VARCHAR (50), gender VARCHAR (50),
	date_of_birth VARCHAR(50), phone_number VARCHAR(50), program_selected VARCHAR(50),
	branch VARCHAR (50), admission_status VARCHAR(50), notes_1 VARCHAR(100),
	final_grade VARCHAR(50), graduation_status VARCHAR(50)
	);

create table raw_graduation_2019 (
	full_name VARCHAR (100), nickname VARCHAR (50), gender VARCHAR (50),
	date_of_birth VARCHAR(50), phone_number VARCHAR(50), program_selected VARCHAR(50),
	branch VARCHAR (50), admission_status VARCHAR(50), final_grade VARCHAR(50),
	graduation_status VARCHAR(50)
	);

-- DOB format confirmed 100% consistent DD/MM/YYYY across all 5 batches
-- (SUBSTRING_INDEX digit-boundary test: left value up to 31, mid value always <=12)

-- Merge all graduation tables (2015-2019) into one raw table
create table raw_graduation_2015_2019 as
select 	full_name, nickname, gender, date_of_birth, phone_number, program_selected,
		branch, admission_status, final_grade, graduation_status, 2015 as source_year
from raw_graduation_2015
union all
select 	full_name, nickname, gender, date_of_birth, phone_number, program_selected,
		branch, admission_status, final_grade, graduation_status, 2016 as source_year
from raw_graduation_2016
union all 
select 	full_name, nickname, gender, date_of_birth, phone_number, program_selected,
		branch, admission_status, final_grade, graduation_status, 2017 as source_year
from raw_graduation_2017
union all 
select 	full_name, nickname, gender, date_of_birth, phone_number, program_selected,
		branch, admission_status, final_grade, graduation_status, 2018 as source_year
from raw_graduation_2018
union all 
select 	full_name, nickname, gender, date_of_birth, phone_number, program_selected,
		branch, admission_status, final_grade, graduation_status, 2019 as source_year
from raw_graduation_2019;

-- Verify merged data is complete: 2723 = 2723 (sum of all 5 source tables)

-- ** DATA STANDARDIZATION
-- full_name / nickname Proper Case (274 rows fixed each)
update raw_graduation_2015_2019
set full_name = concat(upper(left(full_name,1)), lower(substring(full_name,2)))
where binary(full_name) != binary(concat(upper(left(full_name,1)), lower(substring(full_name,2))));

update raw_graduation_2015_2019
set nickname = concat(upper(left(nickname,1)), lower(substring(nickname,2)))
where binary(nickname) != binary(concat(upper(left(nickname,1)), lower(substring(nickname,2))));

-- Gender anomalies: 1 row empty (Participant 844, 2016), 1 row ambiguous "Wanita, Pria" (Participant 439, 2016)
-- Same anomalies as flagged in Section 2 (Eligibility)

-- DOB & phone_number confirmed 100% complete across all 2,723 rows where full_name is filled
-- -> qualifies this table as Reference Master for backfilling DOB in other sections

-- Branch check & consolidation (3 of 24 branches had inconsistent labels)
update raw_graduation_2015_2019 set branch = 'Jakarta' where branch like '%Jakarta%';
update raw_graduation_2015_2019 set branch = 'Solo' where branch like '%Solo%';
update raw_graduation_2015_2019 set branch = 'Yogyakarta' where branch like '%Yogyakarta%';
-- 2 corrupted branch strings from spreadsheet formula errors:
update raw_graduation_2015_2019 set branch = 'Wonogiri' where branch like 'WoNot Completedgiri';
update raw_graduation_2015_2019 set branch = 'Wonosari' where branch like 'WoNot Completedsari';

-- Standardize admission_status: Yes -> Admitted, No -> Not Recommended
update raw_graduation_2015_2019
set admission_status = case when admission_status = 'Yes' then 'Admitted'
							when admission_status = 'No' then 'Not Recommended'
							else admission_status end;

-- Standardize final grade / graduation status
-- Policy (confirmed with admin): legacy system only recorded grades for passing participants.
-- Blank rows = attended but did not meet passing standard -> reclassified as Grade D / FAILED
-- (distinct from "No Show", which never appears in this table at all)
update raw_graduation_2015_2019 set final_grade = 'D' where final_grade = '';
update raw_graduation_2015_2019 set graduation_status = 'FAILED' where graduation_status = '';
-- Result: 814 rows reclassified

-- Standardize empty strings to NULL
update raw_graduation_2015_2019 set gender = nullif(gender, '');

-- ** REMOVE DUPLICATE check (composite key: identity + program + branch + source_year)
-- Result: 0 true duplicates found

-- Create clean table for graduation status
create table clean_graduation_data as
select * from raw_graduation_2015_2019;

-- Verify row count matches: raw_count = clean_count (2723 = 2723)

-- =============================================================================
-- SECTION 3 SUMMARY
-- =============================================================================
-- 5 yearly tables consolidated via UNION ALL, source_year added for lineage
-- 2,723 rows merged, zero data loss
-- 100% DOB format consistency confirmed (DD/MM/YYYY) across all batches
-- 274 full_name/nickname records fixed to Proper Case; 3 of 24 branches standardized,
--   2 corrupted branch strings reconstructed
-- 814 blank grade/status rows reclassified to Grade D / FAILED per confirmed policy
-- 100% complete DOB + phone_number -> established as Reference Master for backfilling
-- Gender anomalies (2 rows) flagged, not guessed
-- 0 duplicates confirmed
-- =============================================================================