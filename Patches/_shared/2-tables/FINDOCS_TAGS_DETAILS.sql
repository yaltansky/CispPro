
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[FINDOCS_TAGS_DETAILS]') AND type in (N'U'))
BEGIN
CREATE TABLE [FINDOCS_TAGS_DETAILS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[TAG_ID] [int] NOT NULL,
	[FINDOC_ID] [int] NOT NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[FINDOCS_TAGS_DETAILS]') AND name = N'IX_FINDOCS_TAGS_DETAILS')
CREATE UNIQUE NONCLUSTERED INDEX [IX_FINDOCS_TAGS_DETAILS] ON [FINDOCS_TAGS_DETAILS]
(
	[TAG_ID] ASC,
	[FINDOC_ID] ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiud_findocs_tags_details]'))
EXEC sp_executesql @statement = N'
create trigger [tiud_findocs_tags_details] on [FINDOCS_TAGS_DETAILS]
for insert, update, delete
as
begin

	set nocount on;

	update fd
	set has_tags = case when exists(select 1 from findocs_tags_details where findoc_id = fd.findoc_id) then 1 else 0 end
	from findocs fd
	where fd.findoc_id in (
		select findoc_id from inserted union all select findoc_id from deleted
		)
	
end
' 
GO
