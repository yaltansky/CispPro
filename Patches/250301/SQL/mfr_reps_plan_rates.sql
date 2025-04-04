if object_id('mfr_reps_plan_rates') is not null drop proc mfr_reps_plan_rates
go
-- exec mfr_reps_plan_rates 1000, @d_doc_from = '2022-03-01'
create proc mfr_reps_plan_rates
	@mol_id int,	
	@d_doc_from date = null,
	@d_doc_to date = null,
	@version_id int = 0
as
begin

	set @version_id = isnull(
		@version_id,
		(select max(version_id) from mfr_plans_vers) -- последняя версия
		)

	select
		isnull(a.name, '-') as group_name,
		mfr.priority_final as mfr_priority,
		r.d_doc,
		mfr.d_delivery as d_delivery,
		concat(right(datepart(year, r.d_doc), 2), '-', right('00' + cast(datepart(month, r.d_doc) as varchar), 2)) as month_plan,
		mfr.number as mfr_number,
		mfr.agent_name,
		p.name as item_name,
        isnull(g1.name, '-') as item_group_name,
		r.plan_q,
		r.order_q,
		sp.value_work * r.order_q / nullif(sp.quantity,0) as value_work,
        sp.value_ccy * r.order_q / nullif(sp.quantity,0) as value_ccy,
        r.order_q * sp.price_list as value_price,
		concat('#', r.mfr_doc_id) as mfr_doc_hid
	from mfr_r_plans_rates r with(nolock)
		join mfr_sdocs mfr with(nolock) on mfr.doc_id = r.mfr_doc_id
			left join sdocs_products sp with(nolock) on sp.doc_id = mfr.doc_id and sp.product_id = r.item_id
		left join prodmeta_attrs a on a.attr_id = r.product_group_id
		left join products p on p.product_id = r.item_id		
        left join mfr_products_grp1 g1 on g1.product_id = r.item_id
	where r.version_id = @version_id
		and (@d_doc_from is null or isnull(r.d_doc, @d_doc_from) >= @d_doc_from)
		and (@d_doc_to is null or isnull(r.d_doc, @d_doc_to) <= @d_doc_to)
		
end
GO
