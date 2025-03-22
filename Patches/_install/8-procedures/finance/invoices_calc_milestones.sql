if object_id('invoices_calc_milestones') is not null drop proc invoices_calc_milestones
go
create proc invoices_calc_milestones
	@doc_id int = null,
	@docs as app_pkids readonly,
	@trace bit = 0
as
begin

	set nocount on;

begin
	declare @proc_name varchar(50) = object_name(@@procid)
	declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out, @echo = @trace

	declare @tid_msg varchar(max) = concat(@proc_name, '.params:')
	exec tracer_log @tid, @tid_msg
end -- prepare

-- @ids
	declare @ids as app_pkids
		insert into @ids select doc_id from supply_invoices x
		where not exists(select 1 from sdocs_milestones where doc_id = x.doc_id)
			and isnull(x.source_id,0) <> 1 -- кроме источника "КИСП"
			and (@doc_id is null or x.doc_id = @doc_id)
			and (not exists(select 1 from @docs) or x.doc_id in (select id from @docs))

-- @milestones
	declare @milestones table(
		doc_id int,
		milestone_id int,
		d_doc datetime,
		d_fact datetime,
		ratio float,
		ratio_value decimal(18,2),
		progress float,
		primary key (doc_id, milestone_id)
		)

	declare @ms_spec int = 1 -- Подписана спецификация (с поставщиком)
	declare @ms_ready int = 2 -- Уведомление о готовности
	declare @ms_ship int = 3 -- Поступление на склад
	declare @ms_job int = 4 -- ЛЗК

-- Подписана спецификация
	insert into @milestones(doc_id, milestone_id, d_doc, d_fact, ratio, ratio_value, progress)
	select x.doc_id,  @ms_spec, x.d_doc, x.d_doc, isnull(a.ratio,0), isnull(a.ratio,0) * x.value_rur, 1
	from supply_invoices x
		join @ids ids on ids.id = x.doc_id
		left join (
			select 
				doc_id, ratio = try_parse(substring(str1, 1, charindex(';', str1) - 1) as float) / 100
			from (
				select doc_id, str1 = substring(note, charindex('ПроцентАванса', note) + 13, 10)
				from supply_invoices
				where charindex('ПроцентАванса', note) > 0
				) xx
		) a on a.doc_id = x.doc_id

-- Уведомление о готовности
	insert into @milestones(doc_id, milestone_id, d_doc, ratio, ratio_value)
	select x.doc_id,  @ms_ready, isnull(x.d_delivery, x.d_doc + 3),
		1.00 - isnull(m.ratio,0),
		(1.00 - isnull(m.ratio,0)) * x.value_rur
	from supply_invoices x
		join @ids ids on ids.id = x.doc_id
		left join @milestones m on m.doc_id = x.DOC_ID and m.milestone_id = @ms_spec
	where charindex('аванс', x.note) > 0 or charindex('доплата', x.note) > 0

-- Поступило на склад
	insert into @milestones(doc_id, milestone_id, d_doc, ratio, ratio_value)
	select x.doc_id,  @ms_ship, isnull(x.d_delivery, x.d_doc + 3),
		1.00 - isnull(m.ratio,0),
		(1.00 - isnull(m.ratio,0)) * x.value_rur
	from supply_invoices x
		join @ids ids on ids.id = x.doc_id
		left join (
			select doc_id, ratio = sum(ratio) from @milestones
			group by doc_id
		) m on m.doc_id = x.doc_id

-- Выдано в производство
	insert into @milestones(doc_id, milestone_id, d_doc, ratio, ratio_value)
	select x.doc_id, @ms_job, isnull(x.d_delivery, x.d_doc + 3), 0, 0
	from supply_invoices x
		join @ids ids on ids.id = x.doc_id

-- save
	insert into sdocs_milestones(doc_id, milestone_id, d_to, d_to_fact, ratio, ratio_value, progress)
	select doc_id, milestone_id, d_doc, d_fact, ratio, ratio_value, progress
	from @milestones x
end
GO
