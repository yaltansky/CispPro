USE CISP_SHARED
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[UsersLogs]') AND type in (N'U'))
BEGIN
CREATE TABLE [UsersLogs](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[UserId] [int] NULL,
	[Url] [varchar](1024) NULL,
	[TimeStart] [datetime] NULL,
	[TimeEnd] [datetime] NULL,
	[Request] [varchar](max) NULL,
	[Host] [varchar](128) NULL,
	[Module] [varchar](100) NULL,
PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)
)
END
GO
