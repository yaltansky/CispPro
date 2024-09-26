﻿IF OBJECT_ID('V_PRODUCTS') IS NOT NULL DROP VIEW V_PRODUCTS
GO
-- SELECT TOP 10 * FROM V_PRODUCTS
CREATE VIEW V_PRODUCTS
AS
SELECT
	X.PRODUCT_ID,
	X.NAME,
	X.TYPE_ID,
	TYPE_NAME = TYPES.NAME,
	X.CLASS_ID,
	X.PLAN_GROUP_ID,
	PLAN_GROUP_NAME = PG.NAME,
	X.STATUS_ID,
	STATUS_NAME = STATUSES.NAME,
	X.INNER_NUMBER,
	UNIT_NAME = U.NAME
FROM PRODUCTS X
	JOIN PRODUCTS_TYPES TYPES ON TYPES.TYPE_ID = X.TYPE_ID
	LEFT JOIN PRODUCTS_PLANS_GROUPS PG ON PG.PLAN_GROUP_ID = X.PLAN_GROUP_ID
	JOIN PRODUCTS_STATUSES STATUSES ON STATUSES.STATUS_ID = X.STATUS_ID
	LEFT JOIN PRODUCTS_UNITS U ON U.UNIT_ID = X.UNIT_ID
GO
