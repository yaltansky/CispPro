﻿IF OBJECT_ID('SDOCS_MFR_MATERIALS') IS NOT NULL DROP VIEW SDOCS_MFR_MATERIALS
GO
-- SELECT TOP 10 * FROM SDOCS_MFR_MATERIALS
CREATE VIEW SDOCS_MFR_MATERIALS
AS
SELECT * FROM SDOCS_MFR_CONTENTS WHERE IS_BUY = 1
GO
