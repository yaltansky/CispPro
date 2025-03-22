
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[PAYORDERS_PAYS]') AND type in (N'U'))
BEGIN
CREATE TABLE [PAYORDERS_PAYS](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PAYORDER_ID] [int] NOT NULL,
	[FINDOC_ID] [int] NOT NULL,
	[D_ADD] [datetime] NULL DEFAULT (getdate()),
	[MOL_ID] [int] NULL,
	[DETAIL_ID] [int] NULL,
 CONSTRAINT [PK_PAYORDERS_PAYS] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tid_payorders_pays]'))
EXEC sp_executesql @statement = N'create trigger [tid_payorders_pays] on [PAYORDERS_PAYS]
for insert, delete
as
begin

	set nocount on;
	
	declare @value_ccy decimal(18,2)

	update x
	set count_pays = (
			select count(*)
			from payorders_pays
			where payorder_id = x.payorder_id
			),
		@value_ccy = isnull((
			select sum(value_ccy)
			from findocs
			where findoc_id in (select findoc_id from payorders_pays where payorder_id = x.payorder_id)
			), 0),
		status_id = 
			case
				when abs(x.value_ccy) <= abs(@value_ccy) then 10 -- оплачено
				when status_id = 10 then 
					case 
						when exists(select 1 from payorders_partials where payorder_id = x.payorder_id) then 5
						else 4
					end
				else status_id
			end
	from payorders x
	where x.payorder_id in (select distinct payorder_id from inserted union all select payorder_id from deleted)

end' 
GO
