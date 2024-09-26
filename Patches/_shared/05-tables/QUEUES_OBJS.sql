USE [CISP_SHARED]
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[QUEUES_OBJS]') AND type in (N'U'))
BEGIN
CREATE TABLE [QUEUES_OBJS](
	[QUEUE_ID] [uniqueidentifier] NOT NULL,
	[OBJ_TYPE] [varchar](8) NOT NULL,
	[OBJ_ID] [int] NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[QUEUE_ID] ASC,
	[OBJ_TYPE] ASC,
	[OBJ_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_QUEUES_OBJS_QUEUE_ID]') AND parent_object_id = OBJECT_ID(N'[QUEUES_OBJS]'))
ALTER TABLE [QUEUES_OBJS]  WITH CHECK ADD  CONSTRAINT [FK_QUEUES_OBJS_QUEUE_ID] FOREIGN KEY([QUEUE_ID])
REFERENCES [QUEUES] ([QUEUE_ID])
ON DELETE CASCADE
GO

IF  EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[FK_QUEUES_OBJS_QUEUE_ID]') AND parent_object_id = OBJECT_ID(N'[QUEUES_OBJS]'))
ALTER TABLE [QUEUES_OBJS] CHECK CONSTRAINT [FK_QUEUES_OBJS_QUEUE_ID]
GO
