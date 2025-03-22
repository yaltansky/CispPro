
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PAYORDERS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PAYORDERS](
	[PAYORDER_ID] [int] IDENTITY(1,1) NOT NULL,
	[SUBJECT_ID] [int] NULL,
	[DOCUMENT_ID] [int] NULL,
	[STATUS_ID] [int] NOT NULL CONSTRAINT [DF__PAYORDERS__STATU__246D18E0]  DEFAULT ((0)),
	[MOL_ID] [int] NULL,
	[NUMBER] [nvarchar](100) NULL,
	[AGENT_ID] [int] NULL,
	[RECIPIENT_ID] [int] NULL,
	[DOGOVOR_ID] [int] NULL,
	[D_ADD] [datetime] NOT NULL CONSTRAINT [DF__PAYORDERS__D_ADD__25613D19]  DEFAULT (getdate()),
	[D_PAY_FACT] [datetime] NULL,
	[D_PAY_PLAN] [datetime] NULL,
	[NOTE] [nvarchar](max) NULL,
	[CCY_ID] [nvarchar](3) NULL,
	[VALUE_CCY] [decimal](18, 2) NULL,
	[COUNT_PAYS] [int] NULL,
	[CONTENT] [varchar](max) NULL,
	[HAS_FILES] [bit] NOT NULL CONSTRAINT [DF__PAYORDERS__HAS_F__00FA8AC8]  DEFAULT ((0)),
	[PAYS_PATH] [varchar](250) NULL,
	[REFKEY] [varchar](50) NULL,
	[PROJECTS_NAME] [varchar](250) NULL,
	[PAID_CCY] [decimal](18, 2) NULL,
	[REMAIN_CCY]  AS (isnull([PAID_CCY],(0))-isnull([VALUE_CCY],(0))),
	[RESERVED] [sql_variant] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[ACCOUNT_ID] [int] NULL,
	[VALUE_RUR] [decimal](18, 2) NULL,
	[PARENT_ID] [int] NULL,
	[NAME] [varchar](250) NULL,
	[NODE] [hierarchyid] NULL,
	[HAS_CHILDS] [bit] NULL,
	[IS_DELETED]  AS (case when [STATUS_ID]=(-1) then (1) else (0) end),
	[FOLDER_ID] [int] NULL,
	[FOLDER_SLICE_ID] [int] NULL,
	[TYPE_ID] [int] NULL,
	[BRANCH_ID] [int] NULL,
	[DBNAME] [varchar](32) NULL,
 CONSTRAINT [PK_PAYORDERS] PRIMARY KEY CLUSTERED 
(
	[PAYORDER_ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[PAYORDERS]') AND name = N'IX_PAYORDERS_REFKEY')
CREATE NONCLUSTERED INDEX [IX_PAYORDERS_REFKEY] ON [PAYORDERS]
(
	[REFKEY] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_payorders]'))
EXEC sp_executesql @statement = N'create trigger [tiu_payorders] on [PAYORDERS]
for insert, update as
begin
	
	set nocount on;

	if update(payorder_id)
		update payorders
		set refkey = ''/finance/payorders/'' + cast(payorder_id as varchar)
		where payorder_id in (select payorder_id from inserted)

	if update(value_ccy)
		update x
		set value_rur = x.value_ccy * isnull(cr.rate,1)
		from payorders x
			left join ccy_rates_cross cr on cr.d_doc = x.d_add and cr.from_ccy_id = x.ccy_id and cr.to_ccy_id = ''rur''
		where payorder_id in (select payorder_id from inserted)
end' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_payorders_content]'))
EXEC sp_executesql @statement = N'create trigger [tiu_payorders_content] on [PAYORDERS]
for insert, update as
begin
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	set nocount on;

	update fd
	set content = concat(
			pt.name, '' '',
			fd.number, '' '',
			s.name, '' '',
            s.short_name, '' '',
			mols.name, '' '',
			fd.projects_name, '' '',
			a1.name, '' '',
			a2.name, '' '',
			cast(fd.value_ccy as varchar), '' '',
			fd.note
            )
	from payorders fd
		join payorders_types pt on pt.type_id = fd.type_id
		left join subjects s on s.subject_id = fd.subject_id
		left join mols on mols.mol_id = fd.mol_id
		left join agents a1 on a1.agent_id = fd.agent_id
		left join agents a2 on a2.agent_id = fd.recipient_id
	where fd.payorder_id in (
		select payorder_id from inserted union select payorder_id from deleted
		)

end
' 
GO
