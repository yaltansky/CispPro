﻿IF OBJECT_ID('SDOCS_DEFECTS') IS NOT NULL DROP VIEW SDOCS_DEFECTS
GO
-- SELECT TOP 10 * FROM SDOCS_DEFECTS
CREATE VIEW SDOCS_DEFECTS
AS
SELECT 
	X.DOC_ID,
	X.EXTERN_ID,
	X.ACC_REGISTER_ID,
    ACC_REGISTER_NAME = acc.NAME,
	X.PLAN_ID,
	X.D_DOC,
	X.NUMBER,	
	X.STATUS_ID,
	STATUS_NAME = ST.NAME,
	X.SUBJECT_ID,
	SUBJECT_NAME = SUBJECTS.SHORT_NAME,
	SUBJECT_PRED_NAME = A.NAME,
	X.PLACE_ID,
	PLACE_NAME = PL.FULL_NAME,
	X.MOL_ID,
	X.NOTE,
	X.CONTENT,
	X.ADD_DATE,
	X.ADD_MOL_ID,
	MOL_NAME = M1.NAME,
	ADD_MOL_NAME = M3.NAME,
	X.UPDATE_DATE,
	X.UPDATE_MOL_ID
FROM SDOCS X WITH(NOLOCK)
	LEFT JOIN ACCOUNTS_REGISTERS ACC ON ACC.ACC_REGISTER_ID = X.ACC_REGISTER_ID
    JOIN SDOCS_TYPES TP WITH(NOLOCK) ON TP.TYPE_ID = X.TYPE_ID
	LEFT JOIN SUBJECTS WITH(NOLOCK) ON SUBJECTS.SUBJECT_ID = X.SUBJECT_ID
		LEFT JOIN AGENTS A WITH(NOLOCK) ON A.AGENT_ID = SUBJECTS.PRED_ID
	LEFT JOIN MFR_PLACES PL WITH(NOLOCK) ON PL.PLACE_ID = X.PLACE_ID
	LEFT JOIN SDOCS_STATUSES ST WITH(NOLOCK) ON ST.STATUS_ID = X.STATUS_ID
	LEFT JOIN MOLS AS M1 WITH(NOLOCK) ON M1.MOL_ID = X.MOL_ID
	LEFT JOIN MOLS AS M3 WITH(NOLOCK) ON M3.MOL_ID = X.ADD_MOL_ID
WHERE X.TYPE_ID = 20
GO
