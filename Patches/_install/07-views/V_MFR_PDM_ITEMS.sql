﻿IF OBJECT_ID('V_MFR_PDM_ITEMS') IS NOT NULL DROP VIEW V_MFR_PDM_ITEMS
GO
-- SELECT TOP 100 * FROM V_MFR_PDM_ITEMS
CREATE VIEW V_MFR_PDM_ITEMS
AS
SELECT 
	X.ID,
	SORT_ID = ISNULL(X.PARENT_ID, X.ID),
	X.PDM_ID,
	X.PLACE_ID,
	X.NUMPOS,
	X.PARENT_ID,
	PARENT_ITEM_ID = XP.ITEM_ID,
	HAS_CHILDS = ISNULL(X.HAS_CHILDS,0),
	LEVEL_ID = CASE WHEN X.PARENT_ID IS NOT NULL THEN 2 ELSE 1 END,
	X.PDM_OPTION_ID,
	OPTION_NAME = OPT.NAME,
	X.ITEM_TYPE_ID,
	ITEM_TYPE_NAME = IT.NAME,
	ITEM_TYPE_SORT = IT.SORT_ID,
	X.ITEM_ID,
	ITEM_NAME = P.NAME,
    X.ITEM_VERSION,
	U.UNIT_ID,
	X.UNIT_NAME,
	X.Q_NETTO,
	X.Q_BRUTTO,
	X.IS_BUY,
	X.ADD_DATE,
	X.ADD_MOL_ID,
	X.UPDATE_DATE,
	X.UPDATE_MOL_ID,
	X.IS_DELETED
FROM MFR_PDM_ITEMS X WITH(NOLOCK)
	JOIN MFR_PDMS D WITH(NOLOCK) ON D.PDM_ID = X.PDM_ID AND D.IS_DELETED = 0
	JOIN PRODUCTS P WITH(NOLOCK) ON P.PRODUCT_ID = X.ITEM_ID
	LEFT JOIN MFR_PDM_ITEMS XP WITH(NOLOCK) ON XP.PDM_ID = X.PDM_ID AND XP.ID = X.PARENT_ID
	LEFT JOIN MFR_PDM_OPTIONS OPT ON OPT.PDM_OPTION_ID = X.PDM_OPTION_ID
	LEFT JOIN PRODUCTS_UNITS U ON U.NAME = X.UNIT_NAME
	LEFT JOIN MFR_ITEMS_TYPES IT ON IT.TYPE_ID = X.ITEM_TYPE_ID
WHERE X.IS_DELETED = 0
GO
