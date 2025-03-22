USE CISP_SHARED
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MOLS_LOG]') AND type in (N'U'))
BEGIN
CREATE TABLE [MOLS_LOG](
	[TRAN_ID] [uniqueidentifier] NULL,
	[TRAN_CALLER] [varchar](max) NULL,
	[TRAN_ACTION] [char](1) NULL,
	[TRAN_USER_ID] [int] NULL,
	[MOL_ID] [int] NULL,
	[NAME] [varchar](255) NULL,
	[TRAN_DATE] [datetime] NULL DEFAULT (getdate())
)
END
GO

