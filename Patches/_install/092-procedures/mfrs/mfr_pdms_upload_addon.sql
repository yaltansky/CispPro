if object_id('mfr_pdms_upload_addon') is not null drop proc mfr_pdms_upload_addon
go
create proc mfr_pdms_upload_addon
as
begin
	
	-- #pdm
		update h set
			item_id = p.product_id
		from #pdm h
			join (
				select
					p.product_id,
					drawing = right(p.name, charindex('(', reverse(p.name)))
				from products p
				where (right(ltrim(rtrim(p.name)), 1) = ')')
					and (charindex('(', p.name) != 0)
			) p on p.drawing = '(' + h.DrawingNo + ')'

		update #pdm set item_name = concat('(', DrawingNo, ')')
		where item_id is null
	
	-- #pdm_items
	update i set
		item_id = p.product_id
	from #pdm_items i
		join products p on (p.name like '[[]' + i.ExternalId + '] %')

	--
	update i set
		item_id = p.product_id
	from 
		#pdm_items i
			join (
				select
					p.product_id,
					drawing = right(p.name, charindex('(', reverse(p.name)))
				from products p
				where (right(ltrim(rtrim(p.name)), 1) = ')')
					and (charindex('(', p.name) != 0)
			) p on p.drawing = '(' + i.DrawingNo + ')'
	where
		(i.item_id is null)

	-- если item_id не нашли, сформируем item_name для авто-добавления
		update #pdm set
			item_name =
				concat(
					'// ',
					PdmItemName,
					' (' + nullif(DrawingNo, '') +')'
				)
			where item_id is null
		--
		update #pdm_items set
			item_name = 
				concat(
					'/', ExternalId, '/ ',
					ItemName,
					' (' + nullif(DrawingNo, '') +')'
				)
			where item_id is null

end
GO
