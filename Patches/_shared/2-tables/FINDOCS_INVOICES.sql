
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[FINDOCS_INVOICES]') AND type in (N'U'))
BEGIN
CREATE TABLE [FINDOCS_INVOICES](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[FINDOC_ID] [int] NULL,
	[INVOICE_ID] [int] NULL,
	[VALUE_CCY] [decimal](18, 2) NULL,
	[VALUE_RUR] [float] NULL,
	[NOTE] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[DBNAME] [varchar](32) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

