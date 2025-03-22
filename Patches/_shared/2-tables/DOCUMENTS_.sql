
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DOCUMENTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [DOCUMENTS](
	[TENANT_ID] [int] NOT NULL DEFAULT ((1)),
	[DOCUMENT_ID] [int] IDENTITY(1,1) NOT NULL,
	[ACCOUNT_LEVEL_ID] [int] NULL,
	[REF_DOCUMENT_ID] [int] NULL,
	[KEY_ATTACHMENTS] [varchar](250) NULL,
	[KEY_OWNER] [varchar](250) NULL,
	[KEY_OWNER_ID] [int] NULL,
	[D_DOC] [datetime] NOT NULL DEFAULT (getdate()),
	[MOL_ID] [int] NOT NULL DEFAULT ((-25)),
	[NAME] [varchar](250) NULL,
	[TAGS] [varchar](max) NULL,
	[NOTE] [varchar](max) NULL,
	[HAS_FILES] [bit] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[RESERVED] [int] NULL,
	[NODE] [hierarchyid] NULL,
	[PARENT_ID] [int] NULL,
	[LEVEL_ID] [int] NULL,
	[SORT_ID] [float] NULL,
	[HAS_CHILDS] [bit] NOT NULL DEFAULT ((0)),
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[STATUS_ID] [int] NOT NULL DEFAULT ((0)),
	[CONTENT] [varchar](max) NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[SUBJECT_ID] [int] NULL,
	[AGENT_ID] [int] NULL,
	[NUMBER] [varchar](150) NULL,
	[EXT_NUMBER] [varchar](150) NULL,
	[HAS_ORIGINAL] [bit] NULL,
	[RESPONSE_ID] [int] NULL,
	[D_EXPIRED] [datetime] NULL,
	[RESPONSE_D_ALERTED] [datetime] NULL,
	[INHERITED_ACCESS] [bit] NULL,
	[TYPE_ID] [int] NOT NULL DEFAULT ((1)),
	[VALUE_CCY] [decimal](18, 2) NULL,
	[CCY_ID] [char](3) NULL,
	[TEMP_AGENT_NAME] [varchar](200) NULL,
	[LAST_AGREE_ID] [int] NULL,
	[D_AGREE_DEADLINE] [datetime] NULL,
	[OWNER_NAME] [varchar](255) NULL,
	[EXTERNAL_ID] [int] NULL,
	[FOLDER_ID] [int] NULL,
	[EXTERN_ID] [varchar](100) NULL,
	[REFKEY] [varchar](50) NULL,
 CONSTRAINT [PK_DOCUMENTS] PRIMARY KEY CLUSTERED 
(
	[DOCUMENT_ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[DOCUMENTS]') AND name = N'IX_DOCUMENTS')
CREATE NONCLUSTERED INDEX [IX_DOCUMENTS] ON [DOCUMENTS]
(
	[D_DOC] ASC,
	[NUMBER] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[DOCUMENTS]') AND name = N'IX_DOCUMENTS_NODE')
CREATE NONCLUSTERED INDEX [IX_DOCUMENTS_NODE] ON [DOCUMENTS]
(
	[NODE] ASC
)
GO
SET ANSI_PADDING ON

GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[DOCUMENTS]') AND name = N'IX_DOCUMENTS_REFKEY')
CREATE NONCLUSTERED INDEX [IX_DOCUMENTS_REFKEY] ON [DOCUMENTS]
(
	[REFKEY] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_documents]'))
EXEC sp_executesql @statement = N'create trigger [tiu_documents] on [DOCUMENTS]
for insert, update as
begin
	
	set nocount on;

	if dbo.sys_triggers_enabled() = 0 return -- disabled

	if update(refkey)
		update documents
		set refkey = concat(''/documents/'', document_id)
		where document_id in (select document_id from inserted)

	if update(is_deleted) or update(status_id)
	begin
		declare @counts int = (select count(*) from inserted where is_deleted = 1 and has_childs = 0)
		if @counts > 10
		begin
			raiserror(''Удаление большого числа документов (всего: %d) невозможно. Транзакция отменена.'', 16, 1, @counts)
			rollback
		end
	end
end
' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_documents_content]'))
EXEC sp_executesql @statement = N'create trigger [tiu_documents_content] on [DOCUMENTS]
for insert, update as
begin
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	set nocount on;

	update x
	set content = 
			x.name + ''#''
			+ isnull(x.number,'''') + ''#''
			+ isnull(x.ext_number,'''') + ''#''
			+ isnull(subj.name,'''') + ''#''
			+ isnull(owner_name,'''') + ''#''
			+ isnull(ag.name,'''') + ''#''
			+ isnull(x.temp_agent_name,'''') + ''#''
			+ isnull(x.name,'''') + ''#''
			+ isnull(mols.name,'''') + ''#''
			+ isnull(x.tags,'''') + ''#''
			+ isnull(x.note, '''')
	from documents x
		left join subjects subj on subj.subject_id = x.subject_id
		left join agents ag on ag.agent_id = x.agent_id
		left join mols on mols.mol_id = x.response_id
	where document_id in (
		select document_id from inserted union select document_id from deleted
		)
		
end
' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tu_documents_last_agree]'))
EXEC sp_executesql @statement = N'create trigger [tu_documents_last_agree] on [DOCUMENTS]
for update as
begin
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	set nocount on;

	if update(last_agree_id)
	begin		
		update x
		set status_id = 
				case 
					when last_agree_id is not null then 2 else x.status_id 
				end,
			d_agree_deadline = 
				case 
					when tt.document_id is not null then 
						isnull(tt.d_deadline, dbo.work_day_add(dbo.getday(tt.add_date), 3))						
					else null
				end			
		from documents x
			left join (
				select xd.document_id, max(xt.add_date) as add_date, max(xt.d_deadline) as d_deadline
				from documents xd
					inner join tasks xt on xt.refkey = xd.refkey
				where xt.type_id = 2
					and xt.status_id = 2
				group by xd.document_id
			) tt on tt.document_id = x.document_id
		where x.document_id in (select document_id from inserted)
	end
end
' 
GO
