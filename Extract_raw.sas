Header Part 
----------------------------------------------
Filename:Extract_raw.sas
Author:Nithish M S
Date:9th Mar 2026
Platform:Macos
Description:Extract the raw data set
Input:Excel Sheet
Output:SDTM
Macro used:<>
-----------------------------------------------
Modefication History
NAME:Nithish M S
DATE:09/03/2026
1]USUBJID is Mapped as per CDISC standard[STUDYID-SITEID-SUBJID]
2]RFSTDTC was converted into Numaric to character as per CDISC standards;


/* IMPORT RAW DM DATAFILE  */
PROC IMPORT DATAFILE="/home/u64168920/Project SDTM DM Raw datafile.xlsx" OUT=WORK.DM DBMS=XLSX REPLACE; RUN;

DATA DM1;
    SET WORK.DM;
    STUDYID=STRIP(STUDY);
    DOMAIN="DM";
    SUBJID=STRIP(SUBJID);
    SITEID=STRIP(SITE);
    USUBJID=CATX("-", STUDYID, SITEID, SUBJID);
    
    RFSTDTC=CATX("T", PUT(INPUT(ENRDT, MMDDYY10.), IS8601DA.), PUT(ENRTM, TOD8.));
    RFENDTC = CATX("T", PUT(INPUT(CMPDT, MMDDYY10.), IS8601DA.), PUT(CMPTM, TOD8.));
    RFICDTC = CATX("T", PUT(INPUT(INFDT, MMDDYY10.), IS8601DA.), PUT(INFTM, TOD8.));
    RFPENDTC=RFENDTC;
    
    DTHDTC="";
    DTHFL="";
    INVNAM=STRIP(INV);
    RACE=UPCASE(ETH);
    ETHOT="";
    AGE=AGEUN;
    AGEU="YEARS";
/*     IF AGE NE . THEN AGEU="YEARS"; */
RUN;

PROC SQL;
    CREATE TABLE DM2 AS
    SELECT *,
    CASE
        WHEN UPCASE(GEN) IN ("FEMALE") THEN 'F'
        WHEN UPCASE(GEN) IN ("MALE") THEN 'M'
        ELSE ''
    END AS SEX 
    FROM DM1;
QUIT;

/* IMPORT RAW EXPOSURE DATAFILE */
PROC IMPORT DATAFILE="/home/u64168920/Project SDTM Exposure Raw datafile.xlsx" OUT=WORK.EX DBMS=XLSX REPLACE; RUN;

DATA EX1;
    SET WORK.EX;
    WHERE VISIT="Period-1";
    USUBJID=CATX("-", STRIP(STUDY), STRIP(SITE), STRIP(SUBJID));
    RFXSTDTC=CATX("T", PUT(INPUT(DSDT, MMDDYY10.), IS8601DA.), PUT(DSDTM, TOD8.));
    TRT1=TRT;
    KEEP USUBJID RFXSTDTC TRT1;
RUN;

DATA EX2;
    SET WORK.EX;
    WHERE VISIT="Period-2";
    USUBJID=CATX("-", STRIP(STUDY), STRIP(SITE), STRIP(SUBJID));
    RFXENDTC=CATX("T", PUT(INPUT(DSDT, MMDDYY10.), IS8601DA.), PUT(DSDTM, TOD8.));
    TRT2=TRT;
    KEEP USUBJID RFXENDTC TRT2;
RUN;

PROC SORT DATA=EX1; BY USUBJID; RUN;
PROC SORT DATA=EX2; BY USUBJID; RUN;

DATA EX_MERGED;
    MERGE EX1(IN=A) EX2(IN=B);
    BY USUBJID;
    IF A OR B;
    IF RFXENDTC EQ "" THEN RFXENDTC=RFXSTDTC;
RUN;

PROC SORT DATA=DM2; BY USUBJID; RUN;

DATA DM3;
    MERGE DM2(IN=A) EX_MERGED(IN=B);
    BY USUBJID;
    IF A;
RUN;

/* IMPORT RAW RANDOMIZATION DATAFILE */
PROC IMPORT DATAFILE="/home/u64168920/Project SDTM Randomization Raw datafile.xlsx" OUT=WORK.RND DBMS=XLSX REPLACE; RUN;

PROC SORT DATA=DM3; BY SUBJID; RUN;
PROC SORT DATA=WORK.RND; BY SUBJID; RUN;

DATA DM4;
    MERGE DM3(IN=A) WORK.RND(IN=B DROP=ARMDA ARMA);
    BY SUBJID;
    IF A;
RUN;

DATA DM5;
    SET DM4;
    ARMCD=ARMDP;
    ARM=ARMP;
    
    IF TRT1="REF" AND TRT2="TEST" THEN DO; ATRT="R-T"; ATRTA="REFE-TEST"; END;
    IF TRT1="TEST" AND TRT2="REF" THEN DO; ATRT="T-R"; ATRTA="TEST-REFE"; END;
    
    ACTARMCD=ATRT;
    ACTARM=ATRTA;
    COUNTRY="IND";
    
    KEEP STUDYID DOMAIN USUBJID SUBJID SITEID RFSTDTC RFENDTC RFXSTDTC RFXENDTC RFICDTC RFPENDTC DTHDTC DTHFL INVNAM AGE AGEU SEX RACE ETHOT ARMCD ARM ACTARMCD ACTARM COUNTRY;
RUN;

DATA DM5_CLEAN;
SET DM5;
IF USUBJID = "" THEN DELETE;
RUN;

PROC SQL;
    CREATE TABLE DM_FINAL AS
    SELECT
        STUDYID "Study identifier" LENGTH=8,
        DOMAIN "Domain Abbreviation" LENGTH=2,
        USUBJID "Unique Subject Identifier" LENGTH=50,
        SUBJID "Subject Identifier for the Study" LENGTH=50,
        SITEID "Study Site Identifier" LENGTH=20,
        RFSTDTC "Subject Reference Start Date/Time" LENGTH=25,
        RFENDTC "Subject Reference End Date/Time" LENGTH=25,
        RFXSTDTC "Date/Time of First Study Treatment" LENGTH=25,
        RFXENDTC "Date/Time of Last Study Treatment" LENGTH=25,
        RFICDTC "Date/Time of Informed Consent" LENGTH=25,
        RFPENDTC "Date/Time of End of Participation" LENGTH=25,
        DTHDTC "Date/Time of Death" LENGTH=25,
        DTHFL "Subject Death Flag" LENGTH=2,
        INVNAM "Investigator Name" LENGTH=100,
        AGE "Age" LENGTH=8,
        AGEU "Age Units" LENGTH=6,
        SEX "Sex" LENGTH=2,
        RACE "Race" LENGTH=100,
        ETHOT "Ethnicity Other" LENGTH=100,
        ARMCD "Planned Arm Code" LENGTH=20,
        ARM "Description of Planned Arm" LENGTH=200,
        ACTARMCD "Actual Arm Code" LENGTH=20,
        ACTARM "Description of Actual Arm" LENGTH=200,
        COUNTRY "Country" LENGTH=3
    FROM DM5;
QUIT;

/* OUTPUT IN XPT FORM */
LIBNAME PG1 "/home/u64168920/EPG1V2/data";

DATA PG1.DM(LABEL="Demographics");
    SET DM_FINAL;
RUN;

LIBNAME XPT XPORT "/home/u64168920/EPG1V2/data/SDTM_OUTPUT.XPT";

DATA XPT.DM;
    SET DM_FINAL;
RUN;










