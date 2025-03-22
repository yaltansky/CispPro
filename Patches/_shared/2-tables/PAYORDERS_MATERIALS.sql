
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PAYORDERS_MATERIALS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PAYORDERS_MATERIALS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PAYORDER_ID] [int] NOT NULL,
	[INVOICE_ID] [int] NULL,
	[MILESTONE_ID] [int] NULL,
	[MFR_DOC_ID] [int] NULL,
	[ITEM_ID] [int] NULL,
	[VALUE_CCY] [decimal](18, 2) NULL,
	[VALUE_RUR] [decimal](18, 2) NULL,
	[NOTE] [nvarchar](max) NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[NDS_RATIO] [decimal](5, 4) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_PAYORDERS_MATERIALS_PAYORDER_ID]') AND parent_object_id = OBJECT_ID(N'[PAYORDERS_MATERIALS]'))
ALTER TABLE [PAYORDERS_MATERIALS]  WITH CHECK ADD  CONSTRAINT [FK_PAYORDERS_MATERIALS_PAYORDER_ID] FOREIGN KEY([PAYORDER_ID])
REFERENCES [PAYORDERS] ([PAYORDER_ID])
ON DELETE CASCADE
GO

IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_PAYORDERS_MATERIALS_PAYORDER_ID]') AND parent_object_id = OBJECT_ID(N'[PAYORDERS_MATERIALS]'))
ALTER TABLE [PAYORDERS_MATERIALS] CHECK CONSTRAINT [FK_PAYORDERS_MATERIALS_PAYORDER_ID]
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_payorders_materials]'))
EXEC sp_executesql @statement = N'create trigger [tiu_payorders_materials] on [PAYORDERS_MATERIALS]
for insert, update as
begin

	set nocount on;

    delete from payorders_details
    where payorder_id in (select payorder_id from inserted)

    insert into payorders_details(payorder_id, budget_id, article_id, value_ccy, nds_ratio)
    select payorder_id, 0, 0, sum(value_ccy), max(nds_ratio)
    from payorders_materials
	where payorder_id in (select payorder_id from inserted)
    group by payorder_id

end' 
GO
