/****** Object:  Table [SDOCS_PRODUCTS_DETAILS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[SDOCS_PRODUCTS_DETAILS]') AND type in (N'U'))
BEGIN
CREATE TABLE [SDOCS_PRODUCTS_DETAILS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DOC_ID] [int] NULL,
	[DETAIL_ID] [int] NULL,
	[QUANTITY] [float] NULL,
	[MFR_NUMBER] [varchar](100) NULL,
	[NOTE] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[STOCK_ADDR_ID] [int] NULL,
PRIMARY KEY NONCLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

/****** Object:  Index [IX_SDOCS_PRODUCTS_DETAILS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SDOCS_PRODUCTS_DETAILS]') AND name = N'IX_SDOCS_PRODUCTS_DETAILS')
CREATE CLUSTERED INDEX [IX_SDOCS_PRODUCTS_DETAILS] ON [SDOCS_PRODUCTS_DETAILS]
(
	[DOC_ID] ASC,
	[DETAIL_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Trigger [tid_sdocs_products_details]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tid_sdocs_products_details]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tid_sdocs_products_details] on [SDOCS_PRODUCTS_DETAILS]
for insert, delete as
begin
	set nocount on;

    declare @rows app_pkids
        insert into @rows
        select distinct detail_id
        from (
            select detail_id from inserted
            union all select detail_id from deleted
            ) x

    update x set
        has_details = case when exists(select 1 from sdocs_products_details where detail_id = x.detail_id) then 1 end
	from sdocs_products x
        join @rows r on r.id = x.detail_id
end
' 
GO
