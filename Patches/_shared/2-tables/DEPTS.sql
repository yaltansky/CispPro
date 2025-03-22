USE CISP_SHARED
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[DEPTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [DEPTS](
	[PARENT_ID] [int] NULL,
	[DEPT_ID] [int] NOT NULL,
	[NAME] [varchar](150) NOT NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[LEVEL_ID] [int] NULL,
	[SORT_ID] [float] NULL,
	[HAS_CHILDS] [bit] NOT NULL DEFAULT ((0)),
	[SUBJECT_ID] [int] NULL,
	[NOTE] [varchar](max) NULL,
	[SHORT_NAME] [varchar](30) NULL,
	[CHIEF_ID] [int] NULL,
	[NODE] [hierarchyid] NULL,
	[NODE_ID] [int] NULL,
	[RESOURCE_ID] [int] NULL,
    CONSTRAINT [PK_DEPTS] PRIMARY KEY CLUSTERED 
    (
        [DEPT_ID] ASC
    )
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[DEPTS]') AND name = N'IX_DEPTS')
CREATE UNIQUE NONCLUSTERED INDEX [IX_DEPTS] ON [DEPTS]
(
	[NAME] ASC,
	[SUBJECT_ID] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[ti_depts]'))
EXEC sp_executesql @statement = N'create trigger [ti_depts] on [DEPTS]
for insert
as
begin

	set nocount on;

	update depts
	set node_id = dept_id
	where dept_id in (select dept_id from inserted)

end
' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tu_depts]'))
EXEC sp_executesql @statement = N'create trigger [tu_depts] on [DEPTS]
for update
as
begin

	set nocount on;

	if update(chief_id)
		update x
		set chief_id = i.chief_id
		from mols x
			join inserted i on i.dept_id = x.dept_id
		where isnull(x.chief_id,0) <> isnull(i.chief_id,0)

end
' 
GO

IF NOT EXISTS(SELECT 1 FROM DEPTS WHERE DEPT_ID = 0)
INSERT INTO DEPTS(DEPT_ID, NAME) VALUES(0, 'unknown')
GO
