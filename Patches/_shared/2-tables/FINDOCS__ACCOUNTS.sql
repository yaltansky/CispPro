
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[FINDOCS_ACCOUNTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [FINDOCS_ACCOUNTS](
	[ACCOUNT_ID] [int] IDENTITY(1,1) NOT NULL,
	[NUMBER] [varchar](50) NULL,
	[NAME] [varchar](50) NOT NULL,
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[EXTERNAL_ID] [varchar](max) NULL,
	[NOTE] [varchar](max) NULL,
	[SUBJECT_ID] [int] NULL,
	[CCY_ID] [varchar](3) NOT NULL DEFAULT ('RUR'),
	[SALDO_OUT] [decimal](18, 2) NOT NULL DEFAULT ((0)),
	[LAST_UPLOAD_ID] [int] NULL,
	[SALDO_IN] [decimal](18, 2) NOT NULL DEFAULT ((0)),
	[NODE] [hierarchyid] NULL,
	[NODE_ID] [int] NULL,
	[PARENT_ID] [int] NULL,
	[LEVEL_ID] [int] NULL,
	[SORT_ID] [float] NULL,
	[HAS_CHILDS] [bit] NOT NULL DEFAULT ((0)),
	[LAST_D_DOC] [datetime] NULL,
	[LAST_D_UPLOAD] [datetime] NULL,
 CONSTRAINT [PK_FINDOCS_ACCOUNTS] PRIMARY KEY CLUSTERED 
(
	[ACCOUNT_ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[FINDOCS_ACCOUNTS]') AND name = N'IX_FINDOCS_ACCOUNTS_NUMBER')
CREATE NONCLUSTERED INDEX [IX_FINDOCS_ACCOUNTS_NUMBER] ON [FINDOCS_ACCOUNTS]
(
	[SUBJECT_ID] ASC,
	[NUMBER] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[ti_findocs_accounts]'))
EXEC sp_executesql @statement = N'
create trigger [ti_findocs_accounts] on [FINDOCS_ACCOUNTS]
for insert as
begin

	set nocount on;

	update findocs_accounts
	set node_id = account_id
	where account_id in (select account_id from inserted)

end' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tu_findocs_accounts]'))
EXEC sp_executesql @statement = N'create trigger [tu_findocs_accounts] on [FINDOCS_ACCOUNTS]
for update as
begin

	set nocount on;

    -- delete virtual deleted
        delete fd from findocs fd
            join inserted i on i.account_id = fd.account_id
        where i.is_deleted = 1
            and fd.status_id = -1

    -- check existence
        if exists(
            select 1 from findocs fd
                join inserted i on i.account_id = fd.account_id
            where i.is_deleted = 1
            )
        begin
            RAISERROR(''Нельзя удалить связанные с фин. операциями счета.'', 16, 1)
            ROLLBACK
        end
end' 
GO
