IF OBJECT_ID('V_MFR_PRINT_KD_DIFFS') IS NOT NULL DROP VIEW V_MFR_PRINT_KD_DIFFS
GO
-- SELECT * FROM V_MFR_PRINT_KD_DIFFS
CREATE VIEW V_MFR_PRINT_KD_DIFFS
AS
SELECT X.*,
    DIFF_TYPE = SIGN(D_DIFF),
    STATUS_NAME = ST.NAME,
    STATUS_CSS = ST.CSS,
    STATUS_STYLE = ST.STYLE
FROM (
    SELECT
        MFR_DOC_ID = MFR.DOC_ID,

        TASK_NAME = PT.NAME,
        STATUS_ID = CASE WHEN PT.PROGRESS = 1 THEN 100 ELSE 1 END,

        D_TO_PLAN = ISNULL(RP.D_TO, PT.D_TO),
        D_DIFF = DATEDIFF(D, 
            CASE WHEN RP.TASK_ID IS NOT NULL THEN RP.D_TO ELSE PT.D_TO END,
            CASE WHEN PT.PROGRESS < 1 THEN CAST(GETDATE() AS DATE) ELSE PT.D_TO END
            )
    FROM SDOCS SD
        JOIN SDOCS_MFR MFR ON MFR.DOC_ID = SD.DOC_ID
        -- ссылка на задачу из заказа (главная задача)
        JOIN PROJECTS_TASKS PT0 ON PT0.TASK_ID = MFR.PROJECT_TASK_ID
            -- дочерние задачи (от главной задачи)
            JOIN PROJECTS_TASKS PT ON PT.PROJECT_ID = PT0.PROJECT_ID AND pt.node.IsDescendantOf(pt0.node) = 1
                AND PT.HAS_CHILDS = 0 -- терминальные задачи
                AND PT.IS_DELETED = 0
            -- сохранённый план
            LEFT JOIN (
                SELECT RT.TASK_ID, RT.D_TO
                FROM PROJECTS_REPS_TASKS RT
                    JOIN (
                        SELECT R.PROJECT_ID, REP_ID = MAX(RT.REP_ID)
                        FROM PROJECTS_REPS_TASKS RT
                            JOIN PROJECTS_REPS R ON R.REP_ID = RT.REP_ID
                        GROUP BY R.PROJECT_ID
                    ) RTM ON RTM.REP_ID = RT.REP_ID
            ) RP ON RP.TASK_ID = PT.TASK_ID
    ) X
    JOIN MFR_ITEMS_STATUSES ST ON ST.STATUS_ID = X.STATUS_ID
WHERE D_DIFF > 0
GO
