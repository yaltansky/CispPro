
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[TASKS_ROUTES]') AND type in (N'U'))
BEGIN
CREATE TABLE [TASKS_ROUTES](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[TASK_ID] [int] NOT NULL,
	[NAME] [varchar](250) NOT NULL,
	[MOL_ID] [int] NOT NULL,
	[NOTE] [nvarchar](max) NULL,
	[ALLOW_REJECT] [bit] NULL,
	[D_PLAN] [datetime] NULL,
	[D_SIGN] [datetime] NULL,
	[ADD_DATE] [datetime] NOT NULL CONSTRAINT [DF__TASKS_ROU__ADD_D__3F898CC2]  DEFAULT (getdate()),
	[RESULT_ID] [int] NULL,
 CONSTRAINT [PK__TASKS_RO__3214EC2747AF759E] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tu_tasks_routes]'))
EXEC sp_executesql @statement = N'create trigger [tu_tasks_routes] on [TASKS_ROUTES]
for update
as begin
 
	set nocount on;
	
	if update(d_sign)
	begin
		update t
		set status_id = 
				case
					when not exists(select 1 from tasks_routes where task_id = t.task_id and d_sign is null) then 5
					else t.status_id
				end
		from tasks t
		where t.task_id in (select task_id from inserted)
			and t.type_id in (2,3) -- листы согласования, ознакомления
			and t.status_id = 2
	end

end
' 
GO
