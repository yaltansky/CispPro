
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_DEALS_PRODUCTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_DEALS_PRODUCTS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DEAL_ID] [int] NULL,
	[NAME] [varchar](500) NULL,
	[QUANTITY] [decimal](18, 2) NULL,
	[PRICE_PURE] [decimal](18, 2) NULL,
	[NDS_RATIO] [decimal](18, 2) NULL,
	[MATERIAL_RATIO] [decimal](18, 2) NULL,
	[VALUE_BDR] [decimal](18, 2) NULL,
	[VALUE_BDS] [decimal](18, 2) NULL,
	[VALUE_NDS] [decimal](18, 2) NULL,
	[VALUE_TRANSFER_PURE] [decimal](18, 2) NULL,
	[VALUE_TRANSFER] [decimal](18, 2) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

