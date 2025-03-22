
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[FIN_GOALS]') AND type in (N'U'))
BEGIN
CREATE TABLE [FIN_GOALS](
	[PARENT_ID] [int] NULL,
	[FIN_GOAL_ID] [int] IDENTITY(1,1) NOT NULL,
	[STATUS_ID] [int] NOT NULL DEFAULT ((1)),
	[SUBJECT_ID] [int] NULL,
	[D_FROM] [datetime] NULL,
	[D_TO] [datetime] NULL,
	[NAME] [nvarchar](250) NULL,
	[NOTE] [nvarchar](max) NULL,
	[MOL_ID] [int] NULL,
	[ADD_DATE] [datetime] NOT NULL DEFAULT (getdate()),
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[FOLDER_ID] [int] NULL,
PRIMARY KEY CLUSTERED 
(
	[FIN_GOAL_ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_fin_goals]'))
EXEC sp_executesql @statement = N'create trigger [tiu_fin_goals] on [FIN_GOALS]
for insert, update as
begin
	
	set nocount on;

	if update(d_from) or update(d_to)
	begin
		update x
		set parent_id = (select fin_goal_id from fin_goals where subject_id = x.subject_id and d_to = x.d_from - 1 and status_id >= 0)
		from fin_goals x
		where fin_goal_id in (
			select fin_goal_id from inserted union select fin_goal_id from deleted
			)
	end
end' 
GO
