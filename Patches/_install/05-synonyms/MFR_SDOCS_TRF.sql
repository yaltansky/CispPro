/****** Object:  Synonym [MFR_SDOCS_TRF]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'MFR_SDOCS_TRF' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [MFR_SDOCS_TRF] FOR [V_MFR_SDOCS_TRF]
GO
