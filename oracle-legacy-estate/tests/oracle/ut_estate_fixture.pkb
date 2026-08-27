CREATE OR REPLACE PACKAGE BODY ut_estate_fixture AS

    PROCEDURE start_output_capture IS
        l_lines DBMS_OUTPUT.CHARARR;
        l_count INTEGER := 32767;
    BEGIN
        DBMS_OUTPUT.ENABLE(1000000);
        -- Drain whatever a previous statement left behind so that a test only
        -- sees the output of the call it makes.
        DBMS_OUTPUT.GET_LINES(l_lines, l_count);
    END start_output_capture;

    FUNCTION captured_output RETURN VARCHAR2 IS
        l_lines DBMS_OUTPUT.CHARARR;
        l_count INTEGER := 500;
        l_text  VARCHAR2(32767);
    BEGIN
        DBMS_OUTPUT.GET_LINES(l_lines, l_count);

        FOR i IN 1 .. l_count LOOP
            l_text := l_text || l_lines(i) || CHR(10);
        END LOOP;

        RETURN l_text;
    END captured_output;

    PROCEDURE purge_audit_rows (p_entity_id IN NUMBER) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        DELETE FROM audit_log
        WHERE entity_name = 'INVOICE'
          AND entity_id = p_entity_id;

        COMMIT;
    END purge_audit_rows;

    PROCEDURE purge_generated_audit_rows IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        DELETE FROM audit_log
        WHERE audit_id >= 100000;

        COMMIT;
    END purge_generated_audit_rows;

END ut_estate_fixture;
/
