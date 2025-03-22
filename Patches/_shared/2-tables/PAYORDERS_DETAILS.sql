
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PAYORDERS_DETAILS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PAYORDERS_DETAILS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PAYORDER_ID] [int] NOT NULL,
	[BUDGET_ID] [int] NULL,
	[ARTICLE_ID] [int] NULL,
	[PLAN_CCY] [decimal](18, 2) NULL,
	[ORDER_CCY] [decimal](18, 2) NULL,
	[FACT_CCY] [decimal](18, 2) NULL,
	[VALUE_CCY] [decimal](18, 2) NULL,
	[NOTE] [nvarchar](max) NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[VALUE_RUR]  AS ([VALUE_CCY]),
	[NDS_RATIO] [decimal](5, 4) NULL,
 CONSTRAINT [PK_PAYORDERS_DETAILS] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_PAYORDERS_DETAILS_PAYORDER_ID]') AND parent_object_id = OBJECT_ID(N'[PAYORDERS_DETAILS]'))
ALTER TABLE [PAYORDERS_DETAILS]  WITH CHECK ADD  CONSTRAINT [FK_PAYORDERS_DETAILS_PAYORDER_ID] FOREIGN KEY([PAYORDER_ID])
REFERENCES [PAYORDERS] ([PAYORDER_ID])
ON DELETE CASCADE
GO

IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_PAYORDERS_DETAILS_PAYORDER_ID]') AND parent_object_id = OBJECT_ID(N'[PAYORDERS_DETAILS]'))
ALTER TABLE [PAYORDERS_DETAILS] CHECK CONSTRAINT [FK_PAYORDERS_DETAILS_PAYORDER_ID]
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_payorders_details]'))
EXEC sp_executesql @statement = N'create trigger [tiu_payorders_details] on [PAYORDERS_DETAILS]
for insert, update as
begin

	set nocount on;

	update payorders
	set value_ccy = (select sum(value_ccy) from payorders_details where payorder_id = payorders.payorder_id and is_deleted = 0)
	where payorder_id in (select payorder_id from inserted)

end
' 
GO
