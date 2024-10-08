/****** Object:  Table [PAYORDERS_PAYS]    Script Date: 9/18/2024 3:24:46 PM ******/
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
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
END
GO
/****** Object:  Trigger [tid_payorders_pays]    Script Date: 9/18/2024 3:24:46 PM ******/
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tid_payorders_pays]'))
EXEC dbo.sp_executesql @statement = N'create trigger [tid_payorders_pays] on [PAYORDERS_PAYS]
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

	-- дублирование оплат (нужно убрать, когда будет упразднена репликация оплат)
	if exists(select 1 from inserted)
	begin
		-- Привязка шапки
		delete from payorders_pays_findocs where findoc_id in (select findoc_id from inserted where detail_id is null)
			insert into payorders_pays_findocs(extern_id, findoc_id, subject_id, d_doc, number, account_id, agent_id, budget_id, article_id, ccy_id, value_ccy, note, wbs_bound, add_date, add_mol_id, update_date, update_mol_id)
			select extern_id, findoc_id, subject_id, d_doc, number, account_id, agent_id, budget_id, article_id, ccy_id, value_ccy, note, wbs_bound, add_date, add_mol_id, update_date, update_mol_id
			from findocs
			where findoc_id in (select findoc_id from inserted where detail_id is null)

		-- Привязка детализации
		delete from payorders_pays_findocs where detail_id in (select detail_id from inserted where detail_id is not null)
			insert into payorders_pays_findocs(extern_id, findoc_id, detail_id, subject_id, d_doc, number, account_id, agent_id, budget_id, article_id, ccy_id, value_ccy, note, wbs_bound, add_date, add_mol_id, update_date, update_mol_id)
			select f.extern_id, f.findoc_id, d.id, f.subject_id, f.d_doc, f.number, f.account_id, f.agent_id, f.budget_id, f.article_id, f.ccy_id, f.value_ccy, f.note, f.wbs_bound, f.add_date, f.add_mol_id, f.update_date, f.update_mol_id
			from findocs f
				join findocs_details d on d.findoc_id = f.findoc_id
			where d.id in (select detail_id from inserted where detail_id is not null)
	end	
end' 
GO
