
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'PRODMETA_ATTRS') AND type in (N'U'))
BEGIN
CREATE TABLE PRODMETA_ATTRS(
	ATTR_ID int IDENTITY(1,1) NOT NULL,
	CODE nvarchar(100) NULL,
	NAME nvarchar(250) NULL,
	NOTE nvarchar(max) NULL,
	UNIT_NAME varchar(30) NULL,
	VALUE_TYPE varchar(20) NULL,
	PARENT_ID int NULL,
	HAS_CHILDS bit NULL,
	NODE hierarchyid NULL,
	LEVEL_ID int NULL,
	SORT_ID float NULL,
	IS_DELETED bit NOT NULL DEFAULT ((0)),
	ADD_DATE datetime DEFAULT getdate(),
	ADD_MOL_ID int NULL,
	UPDATE_DATE datetime NULL,
	UPDATE_MOL_ID int NULL,
	SLICE varchar(16) NULL,
	GROUP_NAME varchar(50) NULL,
	GROUP_KEY varchar(16) NULL,
	ATTR_KEY varchar(16) NULL,
	VALUE_TYPE_LIST varchar(max) NULL,
 CONSTRAINT PK_PRODMETA_ATTRS PRIMARY KEY CLUSTERED 
(
	ATTR_ID ASC
)
)
END
GO


IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'PRODMETA_ATTRS') AND name = N'IX_PRODMETA_ATTRS')
CREATE NONCLUSTERED INDEX IX_PRODMETA_ATTRS ON PRODMETA_ATTRS
(
	CODE ASC
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'PRODMETA_ATTRS') AND name = N'IX_PRODMETA_ATTRS2')
CREATE NONCLUSTERED INDEX IX_PRODMETA_ATTRS2 ON PRODMETA_ATTRS
(
	GROUP_KEY ASC
) INCLUDE(ATTR_ID)
GO


IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'tiu_prodmeta_attrs'))
EXEC sp_executesql @statement = N'create trigger tiu_prodmeta_attrs on PRODMETA_ATTRS
for insert, update
as
begin
	if update(code)
		and exists(
				select 1 from prodmeta_attrs 
				where isnull(code, '''') <> '''' 
					and code in (select code from inserted)
				group by code having count(*) > 1
			)
	begin
		select * from prodmeta_attrs where code in (
			select code from prodmeta_attrs where isnull(code, '''') <> '''' group by code having count(*) > 1
			) order by code
		raiserror(''Есть дубликаты по полю CODE. Добавление/обновление отменено.'', 16, 1)
		rollback
	end
end
' 
GO
