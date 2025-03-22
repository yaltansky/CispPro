IF OBJECT_ID('V_MFR_PRINT_MATERIALS_DIFFS') IS NOT NULL DROP VIEW V_MFR_PRINT_MATERIALS_DIFFS
GO
-- SELECT TOP 10 * FROM V_MFR_PRINT_MATERIALS_DIFFS
CREATE VIEW V_MFR_PRINT_MATERIALS_DIFFS
AS
SELECT 
    MFR_DOC_ID,
    
    ST.STATUS_ID,
    ST.NAME as STATUS_NAME,
    ST.CSS as STATUS_CSS,
    ST.STYLE as STATUS_STYLE,    
    PI.NAME as ITEM_NAME,

    SIGN(D_DIFF) as DIFF_TYPE,
    D_TO_PLAN,
    D_DIFF,

	X.UNIT_NAME,
    ISNULL(Q_JOB, Q_MFR) as Q,
    ISNULL(V_JOB, V_MFR) as V
from (
	select
        mfr_doc_id, status_id, item_id, unit_name,
        min(d_mfr_to) as d_to_plan,
        case when max(d_diff) < 0 then min(d_diff) else max(d_diff) end as d_diff,
        sum(q_mfr) as q_mfr,
        sum(v_mfr) as v_mfr,
        sum(q_job) as q_job,
        sum(v_job) as v_job
    from (
        select
            r.mfr_doc_id, r.status_id, r.item_id, r.unit_name, r.d_mfr_to,
            datediff(d, r.d_mfr_to, isnull(r.d_job, cast(getdate() as date))) as d_diff,
            q_mfr,
            r.q_mfr * r.price as v_mfr,
            isnull(r.q_lzk, r.q_job) as q_job,
            isnull(r.q_lzk, r.q_job) * r.price as v_job
        from mfr_r_provides r
            join sdocs_mfr_contents c on c.content_id = r.id_mfr and c.is_buy = 1
        where r.d_mfr_to != isnull(r.d_job, cast(getdate() as date))
            and r.xslice != 'manual'
            and r.q_mfr >= 0.001
            and c.item_type_id not in (select id from dbo.mfr_provides_excl_items(1))
        ) x
    group by mfr_doc_id, status_id, item_id, unit_name
    ) x
    join products pi on pi.product_id = x.item_id
    join mfr_items_statuses st on st.status_id = x.status_id
go
