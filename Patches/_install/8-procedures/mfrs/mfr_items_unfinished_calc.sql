if object_id('mfr_items_unfinished_calc') is not null drop proc mfr_items_unfinished_calc
go
create proc mfr_items_unfinished_calc
	@mol_id int = null
as
begin

	set nocount on;

	declare @docs as app_pkids
	insert into @docs select doc_id from mfr_sdocs where plan_status_id = 1 and status_id between 0 and 99

	declare @contents as app_pkids

	-- mfr_r_items_unfinished
		delete from @contents
		insert into @contents select x.content_id
		from sdocs_mfr_contents x
			join @docs i on i.id = x.mfr_doc_id
			join sdocs_mfr_contents cp on cp.mfr_doc_id = x.mfr_doc_id and cp.product_id = x.product_id and cp.child_id = x.parent_id
			-- исполнена часть операций
			join (
				select content_id, status_id = max(status_id)
				from sdocs_mfr_opers
				group by content_id
			) o1 on o1.content_id = x.content_id and o1.status_id = 100
			-- начата работа над деталью
			join (
				select content_id, status_id = max(status_id)
				from sdocs_mfr_opers
				group by content_id
			) o2 on o2.content_id = cp.content_id and o2.status_id < 100
		where x.is_buy = 0
		
		truncate table mfr_r_items_unfinished

	-- mfr_r_items_unfinished
		insert into mfr_r_items_unfinished(mfr_doc_id, product_id, content_id, status_id, node_id, item_id)
		select x.mfr_doc_id, x.product_id, x.content_id, x.status_id, x.child_id, x.item_id
		from sdocs_mfr_contents x
			join @contents i on i.id = x.content_id

		-- Участок следующей операции - по связи - за последней сделанной операцией
		update x set place_id = onext.place_id
		from mfr_r_items_unfinished x
			join (
				select o.content_id, target_id = min(ol.target_id)
				from (
					select o.content_id, o.oper_id
					from sdocs_mfr_opers o
						join (
							select content_id, number = max(number)
							from sdocs_mfr_opers
							where status_id = 100
							group by content_id
						) olast on olast.content_id = o.content_id and olast.number = o.number
					) o
					join sdocs_mfr_opers_links ol on ol.source_id = o.oper_id
				group by o.content_id
			) o on o.content_id = x.content_id
			join sdocs_mfr_opers onext on onext.oper_id = o.target_id

		-- Суммарная стоимость материалов детали по составу изделия
		update x set materials_v = m.materials_v
		from mfr_r_items_unfinished x
			join (
				select c.mfr_doc_id, c.product_id, c.parent_id,
					materials_v = sum(
						isnull(
							item_value0,
							c.q_brutto_product * pr.price / nullif(isnull(uk.koef,1),0)
						))
				from sdocs_mfr_contents c
					left join mfr_items_prices pr on pr.product_id = c.item_id
					left join products_units u1 on u1.unit_id = pr.unit_id
					left join products_ukoefs uk on uk.product_id = c.item_id and uk.unit_from = u1.name and uk.unit_to = c.unit_name
				where is_buy = 1
				group by c.mfr_doc_id, c.product_id, c.parent_id
			) m on m.mfr_doc_id = x.mfr_doc_id and m.product_id = x.product_id and m.parent_id = x.node_id

		-- Суммарная трудоемкость по составу изделия (по завершённым операциям)
		update x set fact_hours = o.duration_wk
		from mfr_r_items_unfinished x
			join (
				select content_id, duration_wk = sum(duration_wk)
				from sdocs_mfr_opers
				where status_id = 100
				group by content_id
			) o on o.content_id = x.content_id

end
go
