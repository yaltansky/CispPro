/****** Object:  Table [SDOCS_MFR_MILESTONES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[SDOCS_MFR_MILESTONES]') AND type in (N'U'))
BEGIN
CREATE TABLE [SDOCS_MFR_MILESTONES](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DOC_ID] [int] NULL,
	[PRODUCT_ID] [int] NULL,
	[ATTR_ID] [int] NULL,
	[RATIO] [float] NULL,
	[RATIO_VALUE] [decimal](18, 2) NULL,
	[PROGRESS] [float] NULL,
	[D_TO] [date] NULL,
	[D_TO_PLAN] [date] NULL,
	[D_TO_FACT] [date] NULL,
	[D_TO_PREDICT] [date] NULL,
	[DURATION_BUFFER]  AS (datediff(day,[D_TO_PREDICT],[D_TO])),
	[DATE_LAG] [int] NULL,
	[NOTE] [varchar](max) NULL,
	[TALK_ID] [int] NULL,
	[D_TO_PLAN_AUTO] [date] NULL,
	[D_TO_PLAN_HAND] [date] NULL,
	[K_PROVIDED] [float] NULL,
 CONSTRAINT [PK_SDOCS_MFR_MILESTONES] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
)
END
GO

/****** Object:  Index [IX_SDOCS_MFR_MILESTONES]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N'[SDOCS_MFR_MILESTONES]') AND name = N'IX_SDOCS_MFR_MILESTONES')
CREATE UNIQUE NONCLUSTERED INDEX [IX_SDOCS_MFR_MILESTONES] ON [SDOCS_MFR_MILESTONES]
(
	[DOC_ID] ASC,
	[PRODUCT_ID] ASC,
	[ATTR_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
GO
/****** Object:  Trigger [tiu_sdocs_mfr_milestones]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiu_sdocs_mfr_milestones]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tiu_sdocs_mfr_milestones] on [SDOCS_MFR_MILESTONES]
for update as
begin

	set nocount on;

	if update(d_to_plan_auto) or update(d_to_plan_hand)
		update sdocs_mfr_milestones set 
			d_to_plan = isnull(d_to_plan_hand, d_to_plan_auto)
		where id in (select id from inserted)

end' 
GO

/****** Object:  Synonym [SUPPLY_BUYORDERS_MILESTONES]    Script Date: 9/18/2024 3:28:00 PM ******/
IF NOT EXISTS (SELECT * FROM sys.synonyms WHERE name = N'SUPPLY_BUYORDERS_MILESTONES' AND schema_id = SCHEMA_ID(N'dbo'))
CREATE SYNONYM [SUPPLY_BUYORDERS_MILESTONES] FOR [SDOCS_MILESTONES]
GO
