IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'MFR_PDM_DOCS') AND type in (N'U'))
BEGIN
CREATE TABLE MFR_PDM_DOCS(
	PDM_DOC_ID int IDENTITY(1,1) NOT NULL,
	EXTERN_ID varchar(50) NULL,
	PDM_ID int NOT NULL,
	NUMBER varchar(100) NULL,
	NAME varchar(255) NULL,
	NOTE varchar(max) NULL,
	URL varchar(1024) NULL,
	ADD_DATE datetime default getdate(),
	ADD_MOL_ID int NULL,
	UPDATE_DATE datetime NULL,
	UPDATE_MOL_ID int NULL,
	IS_DELETED bit NOT NULL default (0),
	DOC_VERSION varchar(30) NULL
)
END
GO
