if object_id('mfr_docs_align') is not null drop proc mfr_docs_align
go
create proc mfr_docs_align
	@mol_id int,
	@folder_id int,
	@align_buffer int = 0,
	@align_dates_id int = 1 -- 1 от плановой даты выпуска, 2 от даты контракта
as
begin

	set nocount on;

	declare @proc_name varchar(50) = object_name(@@procid)

	if @folder_id = -1 set @folder_id = dbo.objs_buffer_id(@mol_id)

	declare @docs as app_pkids
	insert into @docs exec objs_folders_ids @folder_id = @folder_id, @obj_type = 'MFR'

	declare @calc_by_docs bit = case when (select count(*) from @docs) <= 3 then 1 else 0 end

	declare @plans app_pkids
		insert into @plans select distinct plan_id from sdocs
		where doc_id in (select id from @docs)
			and plan_id is not null

-- check access
	if (
		select count(distinct subject_id) from mfr_plans where plan_id in (select id from @plans)
		) > 1
	begin
		raiserror('Производственные заказы должны быть из одного субъекта учёта.', 16, 1)
		return
	end

	declare @subject_id int = (select top 1 subject_id from mfr_plans where plan_id in (select id from @plans))
	exec mfr_checkaccess @mol_id = @mol_id, @item = @proc_name, @subject_id = @subject_id
    if @@error != 0 return
	
-- align
	if @calc_by_docs = 0 
	begin
		print 'calc by plan'

		declare c_plans cursor local read_only for select id from @plans
		declare @plan_id int

		open c_plans; fetch next from c_plans into @plan_id
			while (@@fetch_status <> -1)
			begin
				if (@@fetch_status <> -2)
				begin
					exec mfr_opers_calc @mol_id = @mol_id, @plan_id = @plan_id
					
						exec mfr_docs_align;2
							@mol_id = @mol_id,
							@folder_id = @folder_id,
							@plan_id = @plan_id,
							@align_buffer = @align_buffer,
							@align_dates_id = @align_dates_id

					exec mfr_opers_calc @mol_id = @mol_id, @plan_id = @plan_id
				end
				fetch next from c_plans into @plan_id
			end
		close c_plans; deallocate c_plans
	end

	else begin
		print 'calc by doc'

		declare c_docs cursor local read_only for select id from @docs
		declare @doc_id int

		open c_docs; fetch next from c_docs into @doc_id
			while (@@fetch_status <> -1)
			begin
				if (@@fetch_status <> -2)
				begin
					exec mfr_opers_calc @mol_id = @mol_id, @doc_id = @doc_id
					
						exec mfr_docs_align;2
							@mol_id = @mol_id,
							@folder_id = @folder_id,
							@doc_id = @doc_id,
							@align_buffer = @align_buffer,
							@align_dates_id = @align_dates_id

					exec mfr_opers_calc @mol_id = @mol_id, @doc_id = @doc_id
				end
				fetch next from c_docs into @doc_id
			end
		close c_docs; deallocate c_docs
	end
end
go

create proc mfr_docs_align;2
	@mol_id int,
	@folder_id int,
	@plan_id int = null,
	@doc_id int = null,
	@align_buffer int = 0,
	@align_dates_id int = 1
as
begin

	update x
	set d_after = dateadd(d, datediff(d, d_issue_calc, case when @align_dates_id = 1 then d_issue_plan else d_delivery end) - isnull(@align_buffer,0), x.opers_from)
	from sdocs_mfr_contents x
		join (
			select c.mfr_doc_id, min(c.content_id) as content_id
			from sdocs_mfr_contents c
				join (
					select mfr_doc_id, min(opers_from) as opers_from
					from sdocs_mfr_contents c
					where is_deleted = 0 and is_buy = 0 and duration_buffer = 0
					group by mfr_doc_id
				) cc on cc.mfr_doc_id = c.mfr_doc_id and cc.opers_from = c.opers_from
			where is_deleted = 0 and is_buy = 0 and duration_buffer = 0
				and c.mfr_doc_id in (select obj_id from objs_folders_details where folder_id = @folder_id)
				and (@plan_id is null or c.plan_id = @plan_id)
				and (@doc_id is null or c.mfr_doc_id = @doc_id)
			group by c.mfr_doc_id
		) xx on xx.content_id = x.content_id
		join sdocs sd on sd.doc_id = x.mfr_doc_id

end
go
