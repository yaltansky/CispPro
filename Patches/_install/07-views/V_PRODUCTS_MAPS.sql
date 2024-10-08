﻿IF OBJECT_ID('V_PRODUCTS_MAPS') IS NOT NULL DROP VIEW V_PRODUCTS_MAPS
GO
-- SELECT TOP 10 * FROM V_PRODUCTS_MAPS
CREATE VIEW V_PRODUCTS_MAPS
AS
SELECT
	X.*,
    PRODUCT_NAME = P.NAME,
    UPDATE_MOL_NAME = MU.NAME
FROM PRODUCTS_MAPS X
	LEFT JOIN PRODUCTS P ON P.PRODUCT_ID = X.PRODUCT_ID
	LEFT JOIN MOLS MU ON MU.MOL_ID = X.UPDATE_MOL_ID
GO
