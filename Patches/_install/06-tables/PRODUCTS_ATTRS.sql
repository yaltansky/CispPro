/****** Object:  Table [PRODUCTS_ATTRS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PRODUCTS_ATTRS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PRODUCTS_ATTRS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PRODUCT_ID] [int] NULL,
	[ATTR_ID] [int] NULL,
	[ATTR_VALUE_ID] [int] NULL,
	[ATTR_VALUE] [nvarchar](max) NULL,
	[ATTR_VALUE_NUMBER] [float] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[ATTR_VALUE_NOTE] [varchar](max) NULL,
 CONSTRAINT [PK__PRODUCTS__3214EC2787E5AF48] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

/****** Object:  Index [IX_PRODUCTS_ATTRS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PRODUCTS_ATTRS]') AND name = N'IX_PRODUCTS_ATTRS')
CREATE UNIQUE NONCLUSTERED INDEX [IX_PRODUCTS_ATTRS] ON [PRODUCTS_ATTRS]
(
	[PRODUCT_ID] ASC,
	[ATTR_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Index [IX_PRODUCTS_ATTRS2]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PRODUCTS_ATTRS]') AND name = N'IX_PRODUCTS_ATTRS2')
CREATE NONCLUSTERED INDEX [IX_PRODUCTS_ATTRS2] ON [PRODUCTS_ATTRS]
(
	[ATTR_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Trigger [tiu_products_attrs]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_products_attrs]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tiu_products_attrs] on [PRODUCTS_ATTRS]
for insert, update
as
begin
	if update(attr_value)
	begin
		update products_attrs set attr_value_number = isnull(try_parse(attr_value as float using ''ru''), attr_value_number)
		where id in (
			select id from inserted
			union select id from deleted
			)
	end

	if update(attr_value_id)
	begin
		declare @table_list_attrs table(attr_id int primary key, value_type_list varchar(max), table_name varchar(100), key_id varchar(64))
			insert into @table_list_attrs(attr_id, value_type_list)
			select distinct pa.attr_id, pa.value_type_list
			from inserted i
				join prodmeta_attrs pa on pa.attr_id = i.attr_id
			where pa.value_type_list like ''table:%''

		declare @table_info varchar(200)
		update @table_list_attrs
		set @table_info = dbo.strtoken(value_type_list, '':'', 2),
			table_name = dbo.strtoken(@table_info, ''/'', 1),
			key_id = dbo.strtoken(@table_info, ''/'', 2)

		declare c_attrs cursor local read_only for 
			select attr_id, table_name, key_id from @table_list_attrs
		
		declare @attr_id int, @table_name varchar(100), @key_id varchar(100)
		
		open c_attrs; fetch next from c_attrs into @attr_id, @table_name, @key_id
			while (@@fetch_status <> -1)
			begin
				if (@@fetch_status <> -2) 
				begin
					select * into #inserted_ti_products_attrs from inserted
					declare @sql nvarchar(max) = ''
					update x set attr_value = xx.name
					from products_attrs x
						join #inserted_ti_products_attrs i on i.id = x.id
						join %table% xx on xx.%key_id% = x.attr_value_id
					where x.attr_id = %attr_id%
					''
					set @sql = replace(@sql, ''%table%'', @table_name)
					set @sql = replace(@sql, ''%key_id%'', @key_id)
					set @sql = replace(@sql, ''%attr_id%'', @attr_id)
					exec sp_executesql @sql
					exec drop_temp_table ''#inserted_ti_products_attrs''
				end
				fetch next from c_attrs into @attr_id, @table_name, @key_id
			end
		close c_attrs; deallocate c_attrs
		
	end
end' 
GO
