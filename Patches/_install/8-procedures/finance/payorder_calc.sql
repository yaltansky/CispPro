if object_id('payorder_calc') is not null drop proc payorder_calc
go
create proc payorder_calc
	@payorder_id int,
	@check_binds bit = 0
as
begin

	set nocount on;	
	set xact_abort on;

	-- projects
		if @check_binds = 0
		begin		
			declare @projects varchar(max)

			update x
			set @projects = (
					select cast(p.name as varchar(max)) + '; ' as [text()]
					from (
						select distinct projects.name
						from payorders_details d
							join budgets on budgets.budget_id = d.budget_id
							join projects on projects.project_id = budgets.project_id
						where payorder_id = x.payorder_id
							and projects.type_id not in (3)
						) p
					for xml path('')
					),
				projects_name = 
					case
						when len(@projects) > 247 then substring(@projects, 1, 247) + '...'
						else substring(@projects, 1, len(@projects) - 1)
					end		
			from payorders x	
			where x.payorder_id = @payorder_id
		end

	-- paid_ccy
		update x
		set paid_ccy = isnull(pays.value_rur, 0)
		from payorders x
			left join (
				select 
					payorder_id,
					abs(sum(value_rur)) as value_rur
				from (
					select
						pp.payorder_id,
						fd.value_rur
					from payorders_pays pp
						join findocs fd on fd.findoc_id = pp.findoc_id and pp.detail_id is null

					union all
					select
						pp.payorder_id,
						fdd.value_rur
					from payorders_pays pp
						join findocs_details fdd on fdd.findoc_id = pp.findoc_id and fdd.id = pp.detail_id
					) fact
				group by payorder_id			
			) pays on pays.payorder_id = x.payorder_id
		where x.payorder_id = @payorder_id

	-- auto-sync details of FINDOCS
		declare @payorder_value decimal(18,2) = (select value_ccy from payorders where payorder_id = @payorder_id)
		declare @findocs_value decimal(18,2) = (
			select sum(value_ccy) from findocs where findoc_id in (
				select findoc_id from payorders_pays where payorder_id = @payorder_id
				)
			)

		if abs(@payorder_value) >= abs(@findocs_value)
		begin
			declare @mol_id int = isnull((select mol_id from payorders where payorder_id = @payorder_id), -25)
                
            if not exists(select 1 from findocs_invoices where findoc_id in (
                select distinct findoc_id from payorders_pays where payorder_id = @payorder_id
                ))
            begin
                insert into findocs_invoices(findoc_id, invoice_id, value_rur, value_ccy, dbname)
                select 
                    p.findoc_id, m.invoice_id, 
                    sum(m.value_rur * f.value_rur / @payorder_value),
                    sum(m.value_ccy * f.value_ccy / @payorder_value),
                    db_name()
                from payorders_materials m
                    join payorders_pays p on p.payorder_id = m.payorder_id
                        join findocs f on f.findoc_id = p.findoc_id
                where m.payorder_id = @payorder_id
                group by p.findoc_id, m.invoice_id

                -- exec payorders_makedetails @mol_id = @mol_id, @payorder_id = @payorder_id, @action = 'MakeMaterials'
                -- else if exists(select 1 from payorders_details where payorder_id = @payorder_id)
                -- exec payorders_makedetails @mol_id = @mol_id, @payorder_id = @payorder_id, @action = 'MakeDetails'
            end
		end
end
go

create proc payorder_calc;10
	@folders as app_pkids readonly
as
begin

	update o
	set folder_id = null,
		folder_slice_id = null
	from payorders o
		join objs_folders_details fd on fd.obj_id = o.payorder_id and fd.obj_type = 'po'
			join @folders i on i.id = fd.folder_id

	update o
	set folder_id = fp.folder_id, 
		folder_slice_id = fd.folder_id
	from payorders o
		join objs_folders_details fd on fd.obj_id = o.payorder_id and fd.obj_type = 'po'
			join objs_folders f2 on f2.folder_id = fd.folder_id and f2.is_deleted = 0
				join @folders i on i.id = f2.folder_id
				join objs_folders fp on fp.folder_id = f2.parent_id and fp.is_deleted = 0
	where fp.name like 'Реестр %-%-%'

end
go
