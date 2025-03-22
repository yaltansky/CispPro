IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'APP_REGISTRY') AND type in (N'U'))
BEGIN
CREATE TABLE APP_REGISTRY(
	ID int IDENTITY PRIMARY KEY,
    -- common
    DBNAME varchar(64),
	REGISTRY_ID varchar(64),
	NAME nvarchar(250),
	NOTE nvarchar(max),
    -- val
	VAL_STRING varchar(max),
	VAL_NUMBER float,
	VAL_DATE datetime,
	VAL_TYPE varchar(20) DEFAULT ('string'),
	VAL_PARAM varchar(250),
	-- tree
    PARENT_ID int,
	HAS_CHILDS bit,
	NODE hierarchyid,
	LEVEL_ID int,
	SORT_ID float,
    -- timestamp
	IS_DELETED bit NOT NULL DEFAULT (0),
	ADD_DATE datetime DEFAULT getdate(),
	ADD_MOL_ID int,
	UPDATE_DATE datetime,
	UPDATE_MOL_ID int
)
END
GO

IF NOT EXISTS (SELECT * FROM SYS.INDEXES WHERE OBJECT_ID = OBJECT_ID('APP_REGISTRY') AND NAME = 'IX_APP_REGISTRY')
CREATE UNIQUE INDEX IX_APP_REGISTRY ON APP_REGISTRY(DBNAME, REGISTRY_ID);
GO
