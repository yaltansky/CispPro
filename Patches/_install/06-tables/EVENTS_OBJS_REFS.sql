/****** Object:  Table [EVENTS_OBJS_REFS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[EVENTS_OBJS_REFS]') AND type in (N'U'))
BEGIN
CREATE TABLE [EVENTS_OBJS_REFS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[EVENT_ID] [int] NULL,
	[OBJ_TYPE] [varchar](8) NULL,
	[OBJ_ID] [int] NULL,
 CONSTRAINT [PK__EVENTS_O__3214EC278D5ADDE9] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
/****** Object:  Index [IX_EVENTS_OBJS_REFS]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[EVENTS_OBJS_REFS]') AND name = N'IX_EVENTS_OBJS_REFS')
CREATE UNIQUE NONCLUSTERED INDEX [IX_EVENTS_OBJS_REFS] ON [EVENTS_OBJS_REFS]
(
	[EVENT_ID] ASC,
	[OBJ_TYPE] ASC,
	[OBJ_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_EVENTS_OBJS_REFS_EVENTS_EVENT_ID]') AND parent_object_id = OBJECT_ID(N'[EVENTS_OBJS_REFS]'))
ALTER TABLE [EVENTS_OBJS_REFS]  WITH CHECK ADD  CONSTRAINT [FK_EVENTS_OBJS_REFS_EVENTS_EVENT_ID] FOREIGN KEY([EVENT_ID])
REFERENCES [EVENTS] ([EVENT_ID])
ON DELETE CASCADE
GO
IF EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_EVENTS_OBJS_REFS_EVENTS_EVENT_ID]') AND parent_object_id = OBJECT_ID(N'[EVENTS_OBJS_REFS]'))
ALTER TABLE [EVENTS_OBJS_REFS] CHECK CONSTRAINT [FK_EVENTS_OBJS_REFS_EVENTS_EVENT_ID]
GO
