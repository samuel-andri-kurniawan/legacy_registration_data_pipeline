-- =============================================================================
-- SECTION 1 : REGISTRANT DATA CLEANING & STANDARDIZATION (2015-2019)
-- =============================================================================

-- **CREATING TABLE :
create table registrant_data_2015_2019 (
	timestamp 			VARCHAR (100),
	full_name			VARCHAR (100),
	nickname			VARCHAR (50),
	gender 				VARCHAR (20),
	date_of_birth 		VARCHAR (20),
	phone_number		VARCHAR (20),
	email_address		VARCHAR (100),
	institution_type	VARCHAR (100),
	program_selected	VARCHAR (100),
	branch				VARCHAR (50)
	);

-- Verify data import :
select * from registrant_data_2015_2019;
select count(*) from registrant_data_2015_2019;
-- Result: row count matches source CSV (4093)

-- ** DATA STANDARDIZATION
-- Standardize full_name column
select distinct (full_name) from registrant_data_2015_2019 order by full_name asc;

select 	full_name,
		concat(upper(left(full_name,1)), lower(substring(full_name,2))) as fixed_name
from registrant_data_2015_2019
where binary(full_name) <> binary(concat(upper(left(full_name,1)), lower(substring(full_name,2))))
order by full_name ASC;

update registrant_data_2015_2019
set full_name = concat(upper(left(full_name,1)), lower(substring(full_name,2)))
where binary(full_name) <> binary(concat(upper(left(full_name,1)), lower(substring(full_name,2))));

-- Standardize nickname column
select distinct (nickname) from registrant_data_2015_2019 order by nickname asc;

update registrant_data_2015_2019
set nickname = concat(upper(left(nickname,1)), lower(substring(nickname,2)))
where binary(nickname) <> binary(concat(upper(left(nickname,1)), lower(substring(nickname,2))));

-- Standardize gender column
select distinct gender from registrant_data_2015_2019;
select distinct *
from registrant_data_2015_2019
where gender = "Wanita, Pria" or gender is null or gender = ""
order by full_name;
-- Result: found 3 records with ambiguous value, cannot be resolved. Left as-is.

-- Check date_of_birth format
select date_of_birth from registrant_data_2015_2019 order by date_of_birth asc;
-- Result: found 9 NULL records, and some years are invalid (e.g. 1111, 1898, 1883)

select 	date_of_birth,
		SUBSTRING_INDEX(date_of_birth,'/',1) as left_number
from registrant_data_2015_2019
where cast(SUBSTRING_INDEX(date_of_birth,'/',1) as unsigned) > 12
order by SUBSTRING_INDEX(date_of_birth,'/',1) desc;

select	date_of_birth,
		SUBSTRING_INDEX(SUBSTRING_INDEX(date_of_birth,'/',2),'/',-1) as mid_number
from registrant_data_2015_2019
where cast(SUBSTRING_INDEX(SUBSTRING_INDEX(date_of_birth,'/',2),'/',-1)as unsigned) > 12
order by SUBSTRING_INDEX(SUBSTRING_INDEX(date_of_birth,'/',2),'/',-1) desc;

with dob as(
select 	date_of_birth,
		SUBSTRING_INDEX(date_of_birth,'/',1) AS left_number,
        SUBSTRING_INDEX(SUBSTRING_INDEX(date_of_birth,'/',2),'/',-1) AS mid_number,
        CASE 
            WHEN SUBSTRING_INDEX(date_of_birth,'/',1) <= 12 AND SUBSTRING_INDEX(SUBSTRING_INDEX(date_of_birth,'/',2),'/',-1) > 12 THEN 'M/D'
            WHEN SUBSTRING_INDEX(date_of_birth,'/',1) > 12 AND SUBSTRING_INDEX(SUBSTRING_INDEX(date_of_birth,'/',2),'/',-1) <= 12 THEN 'D/M'
            WHEN SUBSTRING_INDEX(date_of_birth,'/',1) <= 12 AND SUBSTRING_INDEX(SUBSTRING_INDEX(date_of_birth,'/',2),'/',-1) <= 12 THEN 'unknown'
        END AS format
from registrant_data_2015_2019
)
select COUNT(format) from dob where format = "unknown";
-- Result: 1587 rows unknown format, left as-is

-- Check branch column
select distinct branch from registrant_data_2015_2019 order by branch;

update registrant_data_2015_2019 set branch = 'Solo' where branch like '%Solo%';
update registrant_data_2015_2019 set branch = 'Jakarta' where branch like '%Jakarta%';
update registrant_data_2015_2019 set branch = 'Yogyakarta' where branch like '%Yogyakarta%';

-- Update '' to NULL
update registrant_data_2015_2019 set gender = null where gender = '';
update registrant_data_2015_2019 set date_of_birth = null where date_of_birth = '';

-- Calculate year_grad (registration year, with Oct-Dec rollover to next year)
alter table registrant_data_2015_2019 add column year_grad INT;

SET sql_mode = (SELECT REPLACE(@@sql_mode, 'STRICT_TRANS_TABLES,', ''));

update registrant_data_2015_2019
set year_grad = 
    case
        when month(STR_TO_DATE(SUBSTRING_INDEX(timestamp, ' ', 1), '%d/%m/%Y')) between 10 and 12
            then year(STR_TO_DATE(SUBSTRING_INDEX(timestamp, ' ', 1), '%d/%m/%Y')) + 1
        else year(STR_TO_DATE(SUBSTRING_INDEX(timestamp, ' ', 1), '%d/%m/%Y'))
    end;
-- Note: Participant 2131, timestamp "29/02/2019" is an invalid leap-year date.
-- year_grad intentionally left NULL for this row (logged as known limitation).

-- ** REMOVE DUPLICATE (includes year_grad to avoid dropping valid re-registrations)
with list_row as (
    select *,
        row_number() over (
            partition by full_name, gender, date_of_birth, phone_number, program_selected, branch, year_grad
            order by timestamp asc
        ) as rn
    from registrant_data_2015_2019
)
select rn, COUNT(*) from list_row where rn > 1 group by rn order by rn asc;
-- Result: 637 duplicate rows found (rn=2 to rn=9)

-- New clean table for registrant_data_2015_2019 (v2 — includes year_grad)
create table clean_registrant_data as
select *
from (
    select *,
        row_number() over (
            partition by full_name, gender, date_of_birth, phone_number, program_selected, branch, year_grad
            order by timestamp asc
        ) as rn
    from registrant_data_2015_2019
) as temp
where rn = 1;

alter table clean_registrant_data drop column rn;

-- Final count
select
    (select COUNT(*) from registrant_data_2015_2019) as original_count,
    (select COUNT(*) from clean_registrant_data) as clean_count,
    (select COUNT(*) from registrant_data_2015_2019) - (select COUNT(*) from clean_registrant_data) as rows_dropped;

-- =============================================================================
-- SECTION 1 SUMMARY
-- =============================================================================
-- Raw rows verified: 4,093 (matches source CSV)
-- full_name and nickname converted to Proper Case
-- 3 ambiguous gender records left as-is
-- 1,587 rows flagged 'unknown' DOB format (day & month both <=12)
-- Branch consolidated into 3 of 24 hubs (Solo, Jakarta, Yogyakarta); rest already clean
-- 1 leap-year timestamp anomaly (29/02/2019) logged, year_grad left NULL
-- 637 duplicate rows removed (15.5%) -> final clean_registrant_data: 3,456 rows
-- =============================================================================