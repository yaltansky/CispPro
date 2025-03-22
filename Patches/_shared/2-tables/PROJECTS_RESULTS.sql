
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PROJECTS_RESULTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PROJECTS_RESULTS](
	[PROJECT_ID] [int] NOT NULL,
	[RESULT_ID] [int] IDENTITY(1,1) NOT NULL,
	[CATEGORY_ID] [int] NULL,
	[D_DOC] [datetime] NULL,
	[MOL_ID] [int] NULL,
	[NAME] [varchar](500) NOT NULL,
	[NOTE] [varchar](max) NULL,
	[PROTECTED_TALK_ID] [int] NULL,
	[PUBLIC_TALK_ID] [int] NULL,
	[REFKEY] [varchar](250) NULL,
	[C_LIKES] [int] NULL,
	[C_DISLIKES] [int] NULL,
	[C_VIEWS] [int] NULL,
	[NODE] [hierarchyid] NULL,
	[PARENT_ID] [int] NULL,
	[HAS_CHILDS] [bit] NOT NULL DEFAULT ((0)),
	[LEVEL_ID] [int] NULL DEFAULT ((0)),
	[SORT_ID] [float] NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[UPDATE_DATE] [datetime] NULL,
PRIMARY KEY CLUSTERED 
(
	[RESULT_ID] ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_projects_results]'))
EXEC sp_executesql @statement = N'
create trigger [tiu_projects_results] on [PROJECTS_RESULTS]
for insert, update as
begin
	set nocount on;

	update projects_results 
	set refkey = concat(''/projects/'', project_id, ''/results/'', result_id)
	where result_id in (select result_id from inserted)

end
' 
GO
