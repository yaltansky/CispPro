
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[FINDOCS]') AND type in (N'U'))
BEGIN
CREATE TABLE [FINDOCS](
	[FINDOC_ID] [int] NOT NULL,
	[ACCOUNT_ID] [int] NULL,
	[STATUS_ID] [int] NULL DEFAULT ((0)),
	[D_DOC] [datetime] NULL,
	[NUMBER] [varchar](50) NULL,
	[AGENT_ID] [int] NULL,
	[DOGOVOR_ID] [int] NULL,
	[SUBJECT_ID] [int] NULL,
	[BUDGET_ID] [int] NULL,
	[ARTICLE_ID] [int] NULL,
	[CCY_ID] [char](3) NULL DEFAULT ('RUR'),
	[VALUE_CCY] [decimal](18, 2) NOT NULL,
	[VALUE_RUR] [decimal](18, 2) NULL,
	[NOTE] [varchar](max) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[UNIQUE_ID] [varbinary](32) NULL,
	[HAS_DETAILS] [bit] NULL DEFAULT ((0)),
	[HAS_TAGS] [bit] NULL DEFAULT ((0)),
	[CONTENT] [varchar](max) NULL,
	[TALK_ID] [int] NULL,
	[WBS_BOUND] [bit] NOT NULL DEFAULT ((0)),
	[EXTERN_ID] [int] NULL,
	[HAS_DEALS] [bit] NOT NULL DEFAULT ((0)),
	[FIXED_DETAILS] [bit] NULL,
	[AGENT_INN] [varchar](30) NULL,
	[AGENT_ACC] [varchar](50) NULL,
	[AGENT_ANALYT] [varchar](255) NULL,
	[GOAL_ACCOUNT_ID] [int] NULL,
 CONSTRAINT [PK_FINDOCS] PRIMARY KEY CLUSTERED 
(
	[FINDOC_ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[FINDOCS]') AND name = N'IX_FINDOCS')
CREATE NONCLUSTERED INDEX [IX_FINDOCS] ON [FINDOCS]
(
	[SUBJECT_ID] ASC,
	[D_DOC] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[FINDOCS]') AND name = N'IX_FINDOCS_1')
CREATE NONCLUSTERED INDEX [IX_FINDOCS_1] ON [FINDOCS]
(
	[ACCOUNT_ID] ASC,
	[D_DOC] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[FINDOCS]') AND name = N'IX_FINDOCS_2')
CREATE NONCLUSTERED INDEX [IX_FINDOCS_2] ON [FINDOCS]
(
	[SUBJECT_ID] ASC,
	[EXTERN_ID] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[FINDOCS]') AND name = N'IX_FINDOCS_3')
CREATE NONCLUSTERED INDEX [IX_FINDOCS_3] ON [FINDOCS]
(
	[SUBJECT_ID] ASC,
	[BUDGET_ID] ASC
)
GO


IF not EXISTS (SELECT * FROM sys.fulltext_indexes fti WHERE fti.object_id = OBJECT_ID(N'[FINDOCS]'))
CREATE FULLTEXT INDEX ON [FINDOCS](
[CONTENT] LANGUAGE 'English')
KEY INDEX [PK_FINDOCS]ON ([CATALOG], FILEGROUP [PRIMARY])
WITH (CHANGE_TRACKING = AUTO, STOPLIST = SYSTEM)
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_FINDOCS_FINDOCS_ACCOUNTS]') AND parent_object_id = OBJECT_ID(N'[FINDOCS]'))
ALTER TABLE [FINDOCS]  WITH CHECK ADD  CONSTRAINT [FK_FINDOCS_FINDOCS_ACCOUNTS] FOREIGN KEY([ACCOUNT_ID])
REFERENCES [FINDOCS_ACCOUNTS] ([ACCOUNT_ID])
ON UPDATE CASCADE
GO

IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_FINDOCS_FINDOCS_ACCOUNTS]') AND parent_object_id = OBJECT_ID(N'[FINDOCS]'))
ALTER TABLE [FINDOCS] CHECK CONSTRAINT [FK_FINDOCS_FINDOCS_ACCOUNTS]
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_findocs_0]'))
EXEC sp_executesql @statement = N'
create trigger [tiu_findocs_0] on [FINDOCS]
for insert, update as
begin
	
	set nocount on;

	if dbo.sys_triggers_enabled() = 0 return -- disabled

	if update(account_id) or update(budget_id) or update(article_id)
	begin
		update x 
		set account_id = isnull(x.account_id, 0),
			budget_id = isnull(x.budget_id, 0),
			article_id = isnull(x.article_id, 0)
		from findocs x
			join inserted i on i.findoc_id = x.findoc_id
		where x.account_id is null
			or x.budget_id is null
			or x.article_id is null
	end

end' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_findocs_content]'))
EXEC sp_executesql @statement = N'
create trigger [tiu_findocs_content] on [FINDOCS]
for insert, update as
begin
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	set nocount on;

	update x
	set content = isnull(fa.name,'''') + ''#''
			+ isnull(ag.name, '''') + ''#''
			+ isnull(b.name,'''') + ''#''
			+ isnull(cast(abs(x.value_ccy) as varchar),'''') + ''#''
			+ isnull(x.note, '''')
	from findocs x
		left join findocs_accounts fa on fa.account_id = x.account_id
		left join agents ag on ag.agent_id = x.agent_id
		left join budgets b on b.budget_id = x.budget_id
	where findoc_id in (
		select findoc_id from inserted union select findoc_id from deleted
		)

end' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_findocs_status]'))
EXEC sp_executesql @statement = N'
create trigger [tiu_findocs_status] on [FINDOCS]
for insert, update
as
begin
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	set nocount on;

	if update(budget_id) or update(article_id) or update(has_details)
	begin
		update fd
		set status_id = 
				case 
					when fd.status_id = -1 then -1
					when fd.has_details = 1 then 
						case
							when exists(select 1 from findocs_details where findoc_id = fd.findoc_id and (isnull(budget_id,0) = 0 or isnull(article_id,0) = 0)) 
								then 0
							else 1
						end
					when isnull(fd.budget_id,0) <> 0 and isnull(fd.article_id,0) <> 0 then 1
					else 0
				end
		from findocs fd
			join inserted i on i.findoc_id = fd.findoc_id
	end

end

' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_findocs_value_rur]'))
EXEC sp_executesql @statement = N'
create trigger [tiu_findocs_value_rur] on [FINDOCS]
for insert, update as
begin
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	set nocount on;

	if update(account_id) or update(d_doc) or update(ccy_id) or update(value_ccy)
	begin
		update x
		set ccy_id = isnull(a.ccy_id, ''RUR'')
		from findocs x
			join findocs_accounts a on a.account_id = x.account_id
		where findoc_id in (select findoc_id from inserted)
			and x.ccy_id is null

		update findocs
		set value_rur = value_ccy
		where findoc_id in (select findoc_id from inserted)
			and ccy_id = ''RUR''

		update x
		set value_rur = x.value_ccy * cr.rate
		from findocs x
			join ccy_rates_cross cr on cr.d_doc = x.d_doc and cr.from_ccy_id = x.ccy_id and cr.to_ccy_id = ''rur''
		where findoc_id in (select findoc_id from inserted)
			and x.ccy_id <> ''RUR''
	end
end
' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiud_findocs]'))
EXEC sp_executesql @statement = N'
create trigger [tiud_findocs] on [FINDOCS]
for insert, update, delete
as
begin

	set nocount on;

	declare @ids app_pkids
	insert into @ids
	select distinct findoc_id 
	from (
		select findoc_id from inserted
		union select findoc_id from deleted
		) u
	exec findocs#_sync_push @ids
	
end' 
GO
