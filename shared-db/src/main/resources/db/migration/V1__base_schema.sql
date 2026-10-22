-- =====================================================================
-- UK Credit Platform - base schema
-- Originally generated from ERwin model CRDT_UK_v2 (2009). Hand-maintained since.
-- NOTE: column naming follows the mainframe copybook standard (abbrev, _CD, _DT, _FLG)
-- =====================================================================

CREATE SEQUENCE CNSMR_SEQ START WITH 100000;
CREATE SEQUENCE ADDR_SEQ START WITH 500000;
CREATE SEQUENCE ADDR_HIST_SEQ START WITH 1;
CREATE SEQUENCE TRDLN_SEQ START WITH 7000000;
CREATE SEQUENCE TRDLN_HIST_SEQ START WITH 1;
CREATE SEQUENCE PUB_REC_SEQ START WITH 1;
CREATE SEQUENCE ALIAS_SEQ START WITH 1;
CREATE SEQUENCE NTC_SEQ START WITH 1;
CREATE SEQUENCE SRCH_SEQ START WITH 1;
CREATE SEQUENCE ER_SEQ START WITH 1;
CREATE SEQUENCE AUD_SEQ START WITH 1;

-- ---------------------------------------------------------------------
-- Consumer (the data subject)
-- ---------------------------------------------------------------------
CREATE TABLE CONSUMER (
    CNSMR_ID        BIGINT       NOT NULL,
    TITLE_CD        VARCHAR(6),
    FRST_NM         VARCHAR(60)  NOT NULL,
    MID_NM          VARCHAR(60),
    SURNM           VARCHAR(60)  NOT NULL,
    DOB             DATE         NOT NULL,
    GNDR_CD         CHAR(1),
    MATCH_KEY       VARCHAR(80),
    STS_CD          CHAR(1)      DEFAULT 'A' NOT NULL,
    CRTD_TS         TIMESTAMP    NOT NULL,
    UPD_TS          TIMESTAMP,
    CONSTRAINT PK_CONSUMER PRIMARY KEY (CNSMR_ID)
);
CREATE INDEX IX_CONSUMER_MATCH ON CONSUMER (MATCH_KEY);

CREATE TABLE CONSUMER_ALIAS (
    ALIAS_ID        BIGINT       NOT NULL,
    CNSMR_ID        BIGINT       NOT NULL,
    FRST_NM         VARCHAR(60),
    SURNM           VARCHAR(60)  NOT NULL,
    ALIAS_TYP_CD    CHAR(2)      NOT NULL,   -- MN = maiden name, AK = also known as
    CRTD_TS         TIMESTAMP    NOT NULL,
    CONSTRAINT PK_CONSUMER_ALIAS PRIMARY KEY (ALIAS_ID),
    CONSTRAINT FK_ALIAS_CNSMR FOREIGN KEY (CNSMR_ID) REFERENCES CONSUMER (CNSMR_ID)
);

-- ---------------------------------------------------------------------
-- Address (PAF-style) and history links
-- ---------------------------------------------------------------------
CREATE TABLE ADDRESS (
    ADDR_ID         BIGINT       NOT NULL,
    BLDG_NO         VARCHAR(10),
    BLDG_NM         VARCHAR(60),
    LINE1           VARCHAR(80)  NOT NULL,
    LINE2           VARCHAR(80),
    TOWN            VARCHAR(60)  NOT NULL,
    CNTY            VARCHAR(60),
    PSTCD           VARCHAR(10)  NOT NULL,
    UDPRN           VARCHAR(12),
    CRTD_TS         TIMESTAMP    NOT NULL,
    CONSTRAINT PK_ADDRESS PRIMARY KEY (ADDR_ID)
);
CREATE INDEX IX_ADDRESS_PSTCD ON ADDRESS (PSTCD);

CREATE TABLE ADDRESS_HISTORY (
    ADDR_HIST_ID    BIGINT       NOT NULL,
    CNSMR_ID        BIGINT       NOT NULL,
    ADDR_ID         BIGINT       NOT NULL,
    DT_FROM         DATE         NOT NULL,
    DT_TO           DATE,
    ADDR_SRC_CD     CHAR(3)      NOT NULL,   -- CAI = lender feed, ERL = electoral roll, MAN = manual
    CRTD_TS         TIMESTAMP    NOT NULL,
    CONSTRAINT PK_ADDRESS_HISTORY PRIMARY KEY (ADDR_HIST_ID),
    CONSTRAINT FK_ADDRH_CNSMR FOREIGN KEY (CNSMR_ID) REFERENCES CONSUMER (CNSMR_ID),
    CONSTRAINT FK_ADDRH_ADDR FOREIGN KEY (ADDR_ID) REFERENCES ADDRESS (ADDR_ID)
);
CREATE INDEX IX_ADDRH_CNSMR ON ADDRESS_HISTORY (CNSMR_ID);

-- ---------------------------------------------------------------------
-- Lenders (data contributors)
-- ---------------------------------------------------------------------
CREATE TABLE LENDER (
    LNDR_ID         INTEGER      NOT NULL,
    LNDR_REF_CD     CHAR(6)      NOT NULL,
    LNDR_NM         VARCHAR(100) NOT NULL,
    SECTOR_CD       CHAR(3)      NOT NULL,
    ACTV_FLG        CHAR(1)      DEFAULT 'Y' NOT NULL,
    CONSTRAINT PK_LENDER PRIMARY KEY (LNDR_ID),
    CONSTRAINT UQ_LENDER_REF UNIQUE (LNDR_REF_CD)
);

CREATE TABLE ACCOUNT_TYPE_REF (
    ACCT_TYP_CD     CHAR(2)      NOT NULL,
    ACCT_TYP_DESC   VARCHAR(60)  NOT NULL,
    RVLVNG_FLG      CHAR(1)      NOT NULL,
    CONSTRAINT PK_ACCOUNT_TYPE_REF PRIMARY KEY (ACCT_TYP_CD)
);

CREATE TABLE TRADELINE_STATUS_REF (
    STS_CD          CHAR(1)      NOT NULL,
    STS_DESC        VARCHAR(80)  NOT NULL,
    ADVRS_FLG       CHAR(1)      NOT NULL,
    CONSTRAINT PK_TRADELINE_STATUS_REF PRIMARY KEY (STS_CD)
);

-- ---------------------------------------------------------------------
-- Account tradeline (one row per lender account, current position)
-- CR_LMT_AMT is whole pounds. CURR_BAL_PNC is pence. Do not "fix" - feeds depend on it.
-- NB: FK to LENDER goes via LNDR_REF_CD (the 6-char contributor code), not LNDR_ID.
-- ---------------------------------------------------------------------
CREATE TABLE ACCOUNT_TRADELINE (
    TRDLN_ID        BIGINT       NOT NULL,
    CNSMR_ID        BIGINT       NOT NULL,
    LNDR_REF_CD     CHAR(6)      NOT NULL,
    ACCT_NO_HASH    VARCHAR(64)  NOT NULL,
    ACCT_TYP_CD     CHAR(2)      NOT NULL,
    OPEN_DT         DATE         NOT NULL,
    CLOSE_DT        DATE,
    CR_LMT_AMT      INTEGER,
    CURR_BAL_PNC    BIGINT       DEFAULT 0 NOT NULL,
    ACCT_STS_CD     CHAR(1)      NOT NULL,
    ACCT_STS_DT     DATE         NOT NULL,
    PYMT_PRFL       VARCHAR(24),
    DEL_FLG         CHAR(1)      DEFAULT 'N' NOT NULL,
    LAST_UPD_BATCH_ID BIGINT,
    CRTD_TS         TIMESTAMP    NOT NULL,
    UPD_TS          TIMESTAMP,
    CONSTRAINT PK_ACCOUNT_TRADELINE PRIMARY KEY (TRDLN_ID),
    CONSTRAINT FK_TRDLN_CNSMR FOREIGN KEY (CNSMR_ID) REFERENCES CONSUMER (CNSMR_ID),
    CONSTRAINT FK_TRDLN_LNDR FOREIGN KEY (LNDR_REF_CD) REFERENCES LENDER (LNDR_REF_CD),
    CONSTRAINT FK_TRDLN_TYP FOREIGN KEY (ACCT_TYP_CD) REFERENCES ACCOUNT_TYPE_REF (ACCT_TYP_CD)
);
CREATE INDEX IX_TRDLN_CNSMR ON ACCOUNT_TRADELINE (CNSMR_ID);
CREATE UNIQUE INDEX UX_TRDLN_LNDR_ACCT ON ACCOUNT_TRADELINE (LNDR_REF_CD, ACCT_NO_HASH);

CREATE TABLE TRADELINE_HISTORY (
    TRDLN_HIST_ID   BIGINT       NOT NULL,
    TRDLN_ID        BIGINT       NOT NULL,
    SNAP_DT         DATE         NOT NULL,
    ACCT_STS_CD     CHAR(1)      NOT NULL,
    CURR_BAL_PNC    BIGINT       NOT NULL,
    CR_LMT_AMT      INTEGER,
    BATCH_ID        BIGINT,
    CONSTRAINT PK_TRADELINE_HISTORY PRIMARY KEY (TRDLN_HIST_ID),
    CONSTRAINT FK_TRDLNH_TRDLN FOREIGN KEY (TRDLN_ID) REFERENCES ACCOUNT_TRADELINE (TRDLN_ID)
);

-- ---------------------------------------------------------------------
-- Public records (court judgments, insolvencies)
-- CNSMR_ID has no FK: records were loaded from the Registry before consumer matching ran (2011).
-- ---------------------------------------------------------------------
CREATE TABLE COURT_REF (
    CRT_CD          CHAR(4)      NOT NULL,
    CRT_NM          VARCHAR(100) NOT NULL,
    JURIS_CD        CHAR(2)      NOT NULL,   -- EW, SC, NI
    CONSTRAINT PK_COURT_REF PRIMARY KEY (CRT_CD)
);

CREATE TABLE PUBLIC_RECORD (
    PUB_REC_ID      BIGINT       NOT NULL,
    CNSMR_ID        BIGINT       NOT NULL,
    REC_TYP_CD      CHAR(3)      NOT NULL,   -- CCJ, DEC (Scottish decree), BKY, IVA
    CRT_CD          CHAR(4),
    CASE_REF        VARCHAR(20)  NOT NULL,
    JDGMT_DT        DATE         NOT NULL,
    JDGMT_AMT       NUMERIC(12,2),
    SATSFD_DT       DATE,
    CONSTRAINT PK_PUBLIC_RECORD PRIMARY KEY (PUB_REC_ID),
    CONSTRAINT FK_PUBREC_CRT FOREIGN KEY (CRT_CD) REFERENCES COURT_REF (CRT_CD)
);
CREATE INDEX IX_PUBREC_CNSMR ON PUBLIC_RECORD (CNSMR_ID);

CREATE TABLE CONSUMER_NOTICE (
    NTC_ID          BIGINT       NOT NULL,
    CNSMR_ID        BIGINT       NOT NULL,
    NTC_TXT         VARCHAR(1000) NOT NULL,
    CRTD_DT         DATE         NOT NULL,
    EXP_DT          DATE,
    CONSTRAINT PK_CONSUMER_NOTICE PRIMARY KEY (NTC_ID),
    CONSTRAINT FK_NTC_CNSMR FOREIGN KEY (CNSMR_ID) REFERENCES CONSUMER (CNSMR_ID)
);

CREATE TABLE SEARCH_FOOTPRINT (
    SRCH_ID         BIGINT       NOT NULL,
    CNSMR_ID        BIGINT       NOT NULL,
    LNDR_REF_CD     CHAR(6)      NOT NULL,
    SRCH_TYP_CD     CHAR(1)      NOT NULL,   -- H = hard (credit application), S = soft (quotation)
    SRCH_DT         DATE         NOT NULL,
    CONSTRAINT PK_SEARCH_FOOTPRINT PRIMARY KEY (SRCH_ID),
    CONSTRAINT FK_SRCH_CNSMR FOREIGN KEY (CNSMR_ID) REFERENCES CONSUMER (CNSMR_ID)
);

CREATE TABLE ELECTORAL_ROLL (
    ER_ID           BIGINT       NOT NULL,
    CNSMR_ID        BIGINT       NOT NULL,
    ADDR_ID         BIGINT       NOT NULL,
    DT_FROM         DATE         NOT NULL,
    DT_TO           DATE,
    CONSTRAINT PK_ELECTORAL_ROLL PRIMARY KEY (ER_ID),
    CONSTRAINT FK_ER_CNSMR FOREIGN KEY (CNSMR_ID) REFERENCES CONSUMER (CNSMR_ID),
    CONSTRAINT FK_ER_ADDR FOREIGN KEY (ADDR_ID) REFERENCES ADDRESS (ADDR_ID)
);

-- ---------------------------------------------------------------------
-- Platform tables
-- ---------------------------------------------------------------------
CREATE TABLE AUDIT_LOG (
    AUD_ID          BIGINT       NOT NULL,
    ENTITY_NM       VARCHAR(40)  NOT NULL,
    ENTITY_ID       VARCHAR(40)  NOT NULL,
    ACTN_CD         VARCHAR(20)  NOT NULL,
    ACTN_TS         TIMESTAMP    NOT NULL,
    SRC_SVC         VARCHAR(30)  NOT NULL,
    DTL_TXT         VARCHAR(2000),
    CONSTRAINT PK_AUDIT_LOG PRIMARY KEY (AUD_ID)
);

CREATE TABLE SYS_PARAM (
    PARAM_CD        VARCHAR(40)  NOT NULL,
    PARAM_VAL       VARCHAR(200) NOT NULL,
    PARAM_DESC      VARCHAR(400),
    CONSTRAINT PK_SYS_PARAM PRIMARY KEY (PARAM_CD)
);
