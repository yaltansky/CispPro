/****** Object:  Table [FINDOCS_DETAILS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[FINDOCS_DETAILS]') AND type in (N'U'))
BEGIN
CREATE TABLE [FINDOCS_DETAILS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[FINDOC_ID] [int] NULL,
	[BUDGET_ID] [int] NULL,
	[VALUE_CCY] [decimal](18, 2) NULL,
	[NOTE] [varchar](max) NULL,
	[ARTICLE_ID] [int] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[WBS_BOUND] [bit] NOT NULL DEFAULT ((0)),
	[VALUE_RUR] [float] NULL,
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[GOAL_ACCOUNT_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

/****** Object:  Index [IX_FINDOCS_DETAILS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[FINDOCS_DETAILS]') AND name = N'IX_FINDOCS_DETAILS')
CREATE NONCLUSTERED INDEX [IX_FINDOCS_DETAILS] ON [FINDOCS_DETAILS]
(
	[FINDOC_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_FINDOCS_DETAILS_FINDOCS]') AND parent_object_id = OBJECT_ID(N'[FINDOCS_DETAILS]'))
ALTER TABLE [FINDOCS_DETAILS]  WITH CHECK ADD  CONSTRAINT [FK_FINDOCS_DETAILS_FINDOCS] FOREIGN KEY([FINDOC_ID])
REFERENCES [FINDOCS] ([FINDOC_ID])
ON UPDATE CASCADE
GO

IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_FINDOCS_DETAILS_FINDOCS]') AND parent_object_id = OBJECT_ID(N'[FINDOCS_DETAILS]'))
ALTER TABLE [FINDOCS_DETAILS] CHECK CONSTRAINT [FK_FINDOCS_DETAILS_FINDOCS]
GO
/****** Object:  Trigger [tiud_findocs_details]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiud_findocs_details]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tiud_findocs_details] on [FINDOCS_DETAILS]
for insert, update, delete
as
begin

	set nocount on;

	if dbo.sys_triggers_enabled() = 0 return -- disabled

-- value_rur
	update fd
	set value_rur = 
			case
				when f.ccy_id = ''rur'' then fd.value_ccy
				else fd.value_ccy * (f.value_rur / nullif(f.value_ccy,0))
			end
	from findocs_details fd
		join findocs f on f.findoc_id = fd.findoc_id
	where fd.findoc_id in (select findoc_id from inserted)

-- has_details
	update f
	set has_details = case when exists(select 1 from findocs_details where findoc_id = f.findoc_id) then 1 else 0 end
	from findocs f
	where findoc_id in (
		select findoc_id from inserted union all select findoc_id from deleted
		)

-- findocs#
	declare @ids app_pkids
	
	insert into @ids select distinct findoc_id 
	from (
		select findoc_id from inserted
		union select findoc_id from deleted
		) u
	
	exec findocs#_sync_push @ids

-- -- findocs_log
-- 	declare @dbcc varchar(50) = ''dbcc inputbuffer('' + str(@@spid) + '')''
--    declare @inputbuffer table(EventType nvarchar(30), Parameters int, EventInfo varchar(max))
--    insert into @inputbuffer exec(@dbcc)
    
-- 	declare 
-- 		@tran_id uniqueidentifier = newid(),
-- 		@tran_caller varchar(max) = (select top 1 eventinfo from @inputbuffer),
-- 		@tran_user_id int = dbo.sys_user_id(),
-- 		@tran_action char(1) = 	
-- 			case
-- 				when exists(select 1 from inserted) and exists(select 1 from deleted) then ''U''
-- 				when exists(select 1 from inserted) then ''I''
-- 				else ''D''
-- 			end

-- 	insert into findocs_log(
-- 		tran_id, tran_caller, tran_action, tran_user_id,
-- 		id, findoc_id, goal_account_id, budget_id, article_id, value_ccy, value_rur, note, add_date, add_mol_id, update_date, update_mol_id
-- 		)
-- 	select 
-- 		@tran_id, @tran_caller, @tran_action, @tran_user_id,
-- 		*
-- 	from (
-- 		select id, findoc_id, goal_account_id, budget_id, article_id, value_ccy, value_rur, note, add_date, add_mol_id, update_date, update_mol_id
-- 		from inserted where @tran_action in (''I'')
-- 		union all
-- 		select id, findoc_id, goal_account_id, budget_id, article_id, value_ccy, value_rur, note, add_date, add_mol_id, update_date, update_mol_id
-- 		from deleted where @tran_action in (''U'', ''D'')
-- 		) u

end' 
GO
