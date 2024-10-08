/****** Object:  Table [OBJS_FOLDERS_DETAILS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[OBJS_FOLDERS_DETAILS]') AND type in (N'U'))
BEGIN
CREATE TABLE [OBJS_FOLDERS_DETAILS](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[FOLDER_ID] [int] NOT NULL,
	[OBJ_ID] [int] NOT NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NOT NULL,
	[OBJ_TYPE] [varchar](8) NULL,
PRIMARY KEY NONCLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
/****** Object:  Index [IX_OBJS_FOLDERS_DETAILS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[OBJS_FOLDERS_DETAILS]') AND name = N'IX_OBJS_FOLDERS_DETAILS')
CREATE UNIQUE CLUSTERED INDEX [IX_OBJS_FOLDERS_DETAILS] ON [OBJS_FOLDERS_DETAILS]
(
	[FOLDER_ID] ASC,
	[OBJ_TYPE] ASC,
	[OBJ_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_OBJS_FOLDERS_DETAILS_OBJS_FOLDERS_FOLDER_ID]') AND parent_object_id = OBJECT_ID(N'[OBJS_FOLDERS_DETAILS]'))
ALTER TABLE [OBJS_FOLDERS_DETAILS]  WITH CHECK ADD  CONSTRAINT [FK_OBJS_FOLDERS_DETAILS_OBJS_FOLDERS_FOLDER_ID] FOREIGN KEY([FOLDER_ID])
REFERENCES [OBJS_FOLDERS] ([FOLDER_ID])
ON DELETE CASCADE
GO
IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_OBJS_FOLDERS_DETAILS_OBJS_FOLDERS_FOLDER_ID]') AND parent_object_id = OBJECT_ID(N'[OBJS_FOLDERS_DETAILS]'))
ALTER TABLE [OBJS_FOLDERS_DETAILS] CHECK CONSTRAINT [FK_OBJS_FOLDERS_DETAILS_OBJS_FOLDERS_FOLDER_ID]
GO
/****** Object:  Trigger [tid_objs_folders_details]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tid_objs_folders_details]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tid_objs_folders_details] on [OBJS_FOLDERS_DETAILS]
for insert, delete, update
as
begin

	set nocount on;

	if dbo.sys_triggers_enabled() = 0 return -- disabled

	declare @affected table(folder_id int)
	insert into @affected 
	select distinct folder_id from inserted union select folder_id from deleted

	update f
	set counts = isnull(ff.counts,0)
	from objs_folders f
		left join (
			select folder_id, obj_type, count(*) as counts
			from objs_folders_details 
			group by folder_id, obj_type
		) ff on ff.folder_id = f.folder_id and ff.obj_type = f.obj_type
	where f.folder_id in (select folder_id from @affected)

    -- /*
    -- ** TEMP: зеркалирование буфера для Ялтанского
    -- */
    -- declare @mol_id int = isnull(
    --     (select top 1 add_mol_id from inserted),
    --     (select top 1 add_mol_id from deleted)
    -- )
    -- if db_name() = ''cisp2'' and @mol_id in (700,1000)
    -- begin
    --     declare @folder_id int = isnull(
    --         (select top 1 folder_id from inserted),
    --         (select top 1 folder_id from deleted)
    --     )
    --     if @folder_id = dbo.objs_buffer_id(@mol_id)
    --     begin
    --         -- if (select count(*) from inserted) > 30 exec cisp3.dbo.objs_buffer_clear @mol_id
    --         if exists(select 1 from deleted)
    --             delete x from cisp3.dbo.objs_folders_details x
    --                 join deleted d on d.folder_id = x.folder_id and d.obj_type = x.obj_type and d.obj_id = x.obj_id
    --         if exists(select 1 from inserted)
    --             insert into cisp3.dbo.objs_folders_details(folder_id, obj_type, obj_id, add_mol_id)
    --             select folder_id, obj_type, obj_id, add_mol_id
    --             from inserted
    --     end
    -- end

end
' 
GO
