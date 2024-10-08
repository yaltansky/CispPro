/****** Object:  Table [OBJS_LIKES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[OBJS_LIKES]') AND type in (N'U'))
BEGIN
CREATE TABLE [OBJS_LIKES](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[OBJ_TYPE] [varchar](3) NULL,
	[OBJ_ID] [int] NULL,
	[MOL_ID] [int] NULL,
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[RATE_LIKE] [bit] NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
/****** Object:  Index [IX_OBJS_LIKES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[OBJS_LIKES]') AND name = N'IX_OBJS_LIKES')
CREATE UNIQUE NONCLUSTERED INDEX [IX_OBJS_LIKES] ON [OBJS_LIKES]
(
	[OBJ_TYPE] ASC,
	[OBJ_ID] ASC,
	[MOL_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO

/****** Object:  Trigger [tiu_objs_likes]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_objs_likes]'))
EXEC dbo.sp_executesql @statement = N'
create trigger [tiu_objs_likes] on [OBJS_LIKES]
for insert, update as
begin
	
	set nocount on;

	update x
	set c_likes = (select count(*) from objs_likes where obj_type = ''prr'' and obj_id = x.result_id and rate_like = 1),
		c_dislikes = (select count(*) from objs_likes where obj_type = ''prr'' and obj_id = x.result_id and rate_like = 0)
	from projects_results x
	where exists(select 1 from inserted where obj_type = ''prr'' and obj_id = x.result_id)

end' 
GO
