USE [CISP_SHARED]
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MFR_PDMS_REGLAMENTS]') AND type in (N'U'))
BEGIN
CREATE TABLE [MFR_PDMS_REGLAMENTS](
	[EXEC_REGLAMENT_ID] [int] NOT NULL,
	[NAME] [varchar](30) NULL,
 CONSTRAINT [PK_MFR_PDMS_REGLAMENTS] PRIMARY KEY CLUSTERED 
(
	[EXEC_REGLAMENT_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
