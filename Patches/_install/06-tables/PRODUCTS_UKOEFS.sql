/****** Object:  Table [PRODUCTS_UKOEFS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PRODUCTS_UKOEFS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PRODUCTS_UKOEFS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PRODUCT_ID] [int] NULL,
	[UNIT_FROM] [varchar](20) NULL,
	[UNIT_TO] [varchar](20) NULL,
	[KOEF] [float] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
/****** Object:  Index [IX_PRODUCTS_UKOEFS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PRODUCTS_UKOEFS]') AND name = N'IX_PRODUCTS_UKOEFS')
CREATE UNIQUE NONCLUSTERED INDEX [IX_PRODUCTS_UKOEFS] ON [PRODUCTS_UKOEFS]
(
	[PRODUCT_ID] ASC,
	[UNIT_FROM] ASC,
	[UNIT_TO] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Trigger [tiu_products_ukoefs]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_products_ukoefs]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tiu_products_ukoefs] on [PRODUCTS_UKOEFS]
for insert,update
as
begin
	set nocount on;

	insert into products_ukoefs(product_id, unit_from, unit_to, koef)
	select product_id, unit_to, unit_from, 1/koef from inserted x
	where not exists(
        select 1 from products_ukoefs 
        where product_id = x.product_id 
            and unit_from = x.unit_to 
            and unit_to = x.unit_from
        )
end
' 
GO
