
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PLAN_PAYS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PLAN_PAYS](
	[PLAN_PAY_ID] [int] IDENTITY(1,1) NOT NULL,
	[D_DOC] [datetime] NULL,
	[NUMBER] [varchar](30) NULL,
	[STATUS_ID] [int] NULL,
	[PERIOD_ID] [varchar](16) NULL,
	[DIRECTION_ID] [int] NULL,
	[CHIEF_ID] [int] NULL,
	[MOL_ID] [int] NULL,
	[NOTE] [varchar](max) NULL,
	[VALUE_PLAN] [decimal](18, 2) NULL,
	[VALUE_FACT] [decimal](18, 2) NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[CONTENT] [varchar](max) NULL,
	[RESERVED] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[PLAN_PAY_ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_plan_pays_content]'))
EXEC sp_executesql @statement = N'
create trigger [tiu_plan_pays_content] on [PLAN_PAYS]
for insert, update as
begin
	
	if dbo.sys_triggers_enabled() = 0 return -- disabled

	set nocount on;

	update x
	set content = concat(
			  x.number, '' ''
			, d.name, '' ''
			, d.short_name, '' ''
			, m1.name, '' ''
			, m2.name, '' ''
			, x.note) 
	from plan_pays x
		left join depts d on d.dept_id = x.direction_id
		left join mols m1 on m1.mol_id = x.chief_id
		left join mols m2 on m2.mol_id = x.mol_id
	where plan_pay_id in (select plan_pay_id from inserted)

end
' 
GO
