USE CISP_SHARED
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[CCY_RATES]') AND type in (N'U'))
BEGIN
CREATE TABLE [CCY_RATES](
	[DATE_ADD] [date] NOT NULL,
	[CCY_ID] [char](3) NOT NULL,
	[RATE] [float] NOT NULL,
	[DESCRIPTION] [nvarchar](2048) NULL,
 CONSTRAINT [PK_CCY_RATES] PRIMARY KEY CLUSTERED 
(
	[DATE_ADD] ASC,
	[CCY_ID] ASC
)
)
END
GO
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiud_ccy_rates_cross]'))
EXEC sp_executesql @statement = N'
-- CREATE TABLE [CCY_RATES](
-- 	[DATE_ADD] [date] NOT NULL,
-- 	[CCY_ID] [char](3) NOT NULL,
-- 	[RATE] [float] NOT NULL,
-- 	[DESCRIPTION] [nvarchar](2048) NULL,
--  CONSTRAINT [PK_CCY_RATES] PRIMARY KEY CLUSTERED 
-- (
-- 	[DATE_ADD] ASC,
-- 	[CCY_ID] ASC
-- )
-- )
-- GO

create trigger [tiud_ccy_rates_cross] on [CCY_RATES]
FOR INSERT, UPDATE, DELETE 
as
begin

	set nocount on

-- CCY_RATES_CROSS
	delete cr
	from deleted as d
		join ccy_rates_cross as cr on 
				d.date_add = cr.d_doc
			and d.ccy_id = cr.from_ccy_id

-- CROSS CCY (1)
	declare @inserted table (D_DOC datetime, FROM_CCY_ID char(3), TO_CCY_ID char(3), RATE float)

	insert into ccy_rates_cross
		(d_doc, from_ccy_id, to_ccy_id, rate)
	output
		inserted.d_doc, inserted.from_ccy_id, inserted.to_ccy_id, inserted.rate
	into @inserted
	select
		i.date_add, i.ccy_id, rt.ccy_id
		, i.rate / rt.rate
	from inserted as i
		join ccy_rates as rt on				
				rt.date_add = i.date_add
			and rt.rate is not null
	where i.ccy_id <> rt.ccy_id		
		and i.rate is not null		

-- TO_CCY_ID = ''RUR''
	insert into ccy_rates_cross
		(d_doc, from_ccy_id, to_ccy_id, rate)
	output
		inserted.d_doc, inserted.from_ccy_id, inserted.to_ccy_id, inserted.rate
	into @inserted
	select
		i.date_add, i.ccy_id, ''RUR''
		, i.rate		
	from inserted as i
	where i.ccy_id <> ''RUR''
		and i.rate is not null

	delete cr
	from deleted as d
		join ccy_rates_cross as cr on 				
				d.date_add = cr.d_doc
			and d.ccy_id in (cr.to_ccy_id, cr.to_ccy_id)

-- CROSS CCY (2)
	insert into ccy_rates_cross
		(d_doc, from_ccy_id, to_ccy_id, rate)
	output
		inserted.d_doc, inserted.from_ccy_id, inserted.to_ccy_id, inserted.rate
	into @inserted
	select
		i.date_add, rt.ccy_id, i.ccy_id
		, rt.rate / i.rate
	from inserted as i
		join ccy_rates as rt on
				rt.date_add = i.date_add
			and rt.rate is not null
	where i.ccy_id <> rt.ccy_id
		and i.rate is not null
		and not exists(select 1 from ccy_rates_cross where d_doc = i.date_add and from_ccy_id = rt.ccy_id and to_ccy_id = i.ccy_id)

-- FROM_CCY_ID = ''RUR''
	insert into ccy_rates_cross
		(d_doc, from_ccy_id, to_ccy_id, rate)
	output
		inserted.d_doc, inserted.from_ccy_id, inserted.to_ccy_id, inserted.rate
	into @inserted
	select
		i.date_add, ''RUR'', i.ccy_id
		, 1. / i.rate
	from inserted as i
	where i.ccy_id <> ''RUR''
		and i.rate is not null

end
' 
GO
