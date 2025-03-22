USE CISP_SHARED
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MOLS]') AND type in (N'U'))
BEGIN
CREATE TABLE [MOLS](
	[MOL_ID] [int] NOT NULL,
	[NAME] [varchar](100) NULL,
	[DEPT_ID] [int] NULL,
	[POST_ID] [int] NULL,
	[STATUS_ID] [int] NULL DEFAULT ((3)),
	[IS_WORKING] [bit] NOT NULL DEFAULT ((1)),
	[SURNAME] [varchar](50) NULL,
	[NAME1] [varchar](50) NULL,
	[NAME2] [varchar](50) NULL,
	[PHONE] [varchar](50) NULL,
	[PHONE_LOCAL] [int] NULL,
	[ROOM] [varchar](50) NULL,
	[EMAIL] [varchar](50) NULL,
	[NAME_SKYPE] [varchar](50) NULL,
	[BIRTHDAY] [smalldatetime] NULL,
	[IS_MAN] [bit] NULL DEFAULT ((1)),
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[PHONE_MOBILE] [varchar](20) NULL,
	[CITY_ID] [int] NULL,
	[BRANCH_ID] [int] NULL,
	[CHIEF_ID] [int] NULL,
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[NOTE] [varchar](max) NULL,
	[POSTS_NAMES] [varchar](250) NULL,
	[EXTERNAL_ID] [int] NULL,
	[RESOURCE_ID] [int] NULL,
	[SUBJECT_ID] [int] NULL,
	[CITY_NAME] [varchar](50) NULL,
	[DEPTS_NAMES] [varchar](250) NULL,
	[TAB_NUMBER] [varchar](30) NULL,
    CONSTRAINT [PK_MOLS] PRIMARY KEY CLUSTERED 
    (
        [MOL_ID] ASC
    )
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_MOLS_DEPT_ID]') AND parent_object_id = OBJECT_ID(N'[MOLS]'))
ALTER TABLE [MOLS]  WITH CHECK ADD  CONSTRAINT [FK_MOLS_DEPT_ID] FOREIGN KEY([DEPT_ID])
REFERENCES [DEPTS] ([DEPT_ID])
GO

IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_MOLS_DEPT_ID]') AND parent_object_id = OBJECT_ID(N'[MOLS]'))
ALTER TABLE [MOLS] CHECK CONSTRAINT [FK_MOLS_DEPT_ID]
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_MOLS_DEPTS]') AND parent_object_id = OBJECT_ID(N'[MOLS]'))
ALTER TABLE [MOLS]  WITH CHECK ADD  CONSTRAINT [FK_MOLS_DEPTS] FOREIGN KEY([DEPT_ID])
REFERENCES [DEPTS] ([DEPT_ID])
ON UPDATE CASCADE
GO

IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_MOLS_DEPTS]') AND parent_object_id = OBJECT_ID(N'[MOLS]'))
ALTER TABLE [MOLS] CHECK CONSTRAINT [FK_MOLS_DEPTS]
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[ti_mols_defaults]'))
EXEC sp_executesql @statement = N'create trigger [ti_mols_defaults] on [MOLS] 
FOR INSERT
AS
begin

	set nocount on;

	-- defaults
	update mols	set 
		dept_id = isnull(dept_id, 0),
		post_id = isnull(post_id, 0)				
	where mol_id in (select mol_id from inserted)
end -- trigger
' 
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_mols_email]'))
EXEC sp_executesql @statement = N'CREATE TRIGGER [tiu_mols_email] ON [MOLS] 
FOR INSERT, UPDATE
AS
begin

	set nocount on 

	if update(email) and exists(select 1 from inserted where isnull(email,'''') <> '''' and email not like ''%@%.%'')
	begin
		raiserror(''Неверно указан адрес электронной почты. Требуется ввести корректный адрес.'', 16, 1)
		rollback
	end

	if update(email)
		update u
		set email = m.email
		from users u
			inner join mols m on m.mol_id = u.id
		where m.email <> u.email

end
' 
GO

IF object_id('tiu_mols_name') is not null drop trigger tiu_mols_name
GO
create trigger [tiu_mols_name] on [MOLS]
for insert, update
as
begin

	set nocount on 

	if update(surname) or update(name1) or update(name2)
	begin
		declare @surname varchar(max), @name1 varchar(max), @name2 varchar(max)

		update mols
		set @surname = rtrim(ltrim(isnull(surname, '')))
			, @name1 = rtrim(ltrim(isnull(name1, '')))
			, @name2 = rtrim(ltrim(isnull(name2, '')))
			--
			, name = concat(@surname, 
                case when @name1 != '' or @name2 != '' then ' ' end, 
                case when @name1 != '' then left(@name1,1) end, 
                case when @name1 != '' then '.' end, 
                case when @name2 != '' then left(@name2,1) end, 
                case when @name2 != '' then '.' end
                )
			, surname = @surname
			, name1 = @name1
			, name2 = @name2
		where mol_id in (select mol_id from inserted)
	end

end
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_mols_name_logon]'))
EXEC sp_executesql @statement = N'CREATE trigger [tiu_mols_name_logon] on [MOLS]
for insert, update
as
begin

	set nocount on;

	if update(email)
	begin
		if exists(
			select 1 from mols where email is not null and email in (select email from inserted)
				and mol_id not in (select mol_id from inserted)
			)
		begin
			raiserror(''Запись с такими учётными данными (email) уже существует.'', 16, 1)
			rollback
			return
		end
	end

end
' 
GO

if object_id('tiu_mols_post') is not null drop trigger tiu_mols_post
go
create trigger [tiu_mols_post] on [MOLS]
for insert, update
as
begin
	set nocount on 

	if update(post_id)
		update x set posts_names = mp.name
		from mols x
			join inserted i on i.mol_id = x.mol_id
			join mols_posts mp on mp.post_id = x.post_id
		where nullif(x.posts_names, '-') is null

    update mols set post_id = null where mol_id in (select mol_id from inserted)
        and post_id = 0
end
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_mols_status_id]'))
EXEC sp_executesql @statement = N'create trigger [tiu_mols_status_id] on [MOLS]
for insert, update
as
begin

	set nocount on;

	if update (status_id)
	begin
		-- Синхронизация поля IS_WORKING
		update mols set is_working = 
			case 
				when i.status_id in (0, -1, -3) then 0 
				else 1 
			end 
		from mols m
			inner join inserted i on m.mol_id = i.mol_id
	end

	if exists(select 1 from inserted where status_id = -1)
	begin
		delete from users
		where id in (select mol_id from inserted where status_id = -1)
	end

end -- trigger
' 
GO

