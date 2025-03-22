IF OBJECT_ID('MFR_PRODUCTS_GRP1') IS NOT NULL DROP VIEW MFR_PRODUCTS_GRP1
GO
-- SELECT * FROM MFR_PRODUCTS_GRP1
CREATE VIEW MFR_PRODUCTS_GRP1
AS
SELECT 
	PA.PRODUCT_ID,
	A.ATTR_ID,
	A.NAME
from 
	-- avoid duplicates
	(
		select product_id, attr_id = max(pa.attr_id)
		from products_attrs pa with(nolock)
			join prodmeta_attrs a with(nolock) on a.attr_id = pa.attr_id and a.group_key = 'MFRTOTALGRP'
		group by pa.product_id
	) pa 
	join prodmeta_attrs a with(nolock) on a.attr_id = pa.attr_id
GO
