if object_id('events_get_groups') is not null drop proc events_get_groups
go
-- exec events_get_groups @mol_id = 1000, @extra_id = null
create proc events_get_groups
	@mol_id int,
	@extra_id int, -- null - all, 1 - talks, 2 - tasks, -1 - archive
	@search varchar(128) = null,
	@trace bit = 0
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	if @search is not null set @search = '%' + @search + '%'
	
	-- @result
		declare @result table(
			feed_id int,
			task_id int,
			talk_id int,
			owner_mol_id int,
			owner_name varchar(80),
			href varchar(max),
			last_event_id int,
			last_hist_id int,
			last_mol_id int,
			last_message varchar(150),
			last_date datetime,
			count_unreads int
			)

	-- tasks
		declare @now datetime = getdate()

		insert into @result(
			task_id, owner_name, href, last_date, last_hist_id, count_unreads
			)
		select
			t.task_id,
			substring(t.title, 1, 80),
			'/tasks/' + cast(t.task_id as varchar),			
			max(h.d_add),
			max(h.hist_id),
			sum(case when hm.d_read is null then 1 else 0 end)
		from tasks t with(nolock)
			join tasks_hists h with(nolock) on h.task_id = t.task_id				
				join (
					select hist_id, d_read
					from tasks_hists_mols with(nolock)
					where tasks_hists_mols.mol_id = @mol_id
						and (d_read is null or datediff(d, d_read, @now) = 0)
				) hm on hm.hist_id = h.hist_id
		where h.silence = 0
			and (@extra_id is null or @extra_id = 2)
			and (
				@search is null 
				or t.title like @search
				or exists(
					select 1 from tasks_hists th
						join mols on mols.mol_id = th.mol_id
					where task_id = t.task_id 
						and concat(mols.name, th.body) like @search
					)
				)
		group by t.task_id, t.title

		update r
		set owner_mol_id = h.mol_id,
			last_mol_id = h.mol_id,
			last_message = substring(coalesce(h.body, h.description, 'обратная связь по задаче'), 1, 150)
		from @result r
			join tasks_hists h with(nolock) on h.hist_id = r.last_hist_id

	-- talks
		insert into @result(
			talk_id, owner_mol_id, owner_name, href, last_mol_id, last_message, last_date, count_unreads
			)
		select
			e.talk_id,
			isnull(h.mol_id, e.mol_id),
			isnull(substring(e.subject, 1, 80), 'Диалог #' + cast(e.talk_id as varchar)),
			e.[key] + '/' + cast(e.talk_id as varchar),
			isnull(h.mol_id, e.mol_id),
			substring(h.body, 1, 150),
			h.d_add,
			em.count_unreads
		from talks e with(nolock)
			join talks_mols em with(nolock) on em.talk_id = e.talk_id and em.mol_id = @mol_id
			left join talks_hists h with(nolock) on h.hist_id = e.last_hist_id
		where ((isnull(@extra_id,1) = 1 and em.is_deleted = 0) 
				or (@extra_id = -1  and em.is_deleted = 1)
				)
			and (@search is null 
				or e.subject like @search
				or e.body like @search
				or exists(
					select 1 from talks_hists th
						join mols on mols.mol_id = th.mol_id
					where parent_id = e.talk_id 
						and concat(mols.name, th.body) like @search
					)
				)

	-- result
		select
			@mol_id,
			R.FEED_ID,
			R.TASK_ID,
			R.TALK_ID,
			R.OWNER_NAME,
			OWNER_MOL_ID = M.MOL_ID,
			OWNER_MOL_NAME = M.NAME,
			HREF = isnull(r.href,'/events'),
			LAST_MESSAGE = CONCAT(M2.NAME , ': ', LEFT(ISNULL(R.LAST_MESSAGE, E.CONTENT), 100)),
			LAST_DATE = ISNULL(E.ADD_DATE, R.LAST_DATE),
			R.COUNT_UNREADS
		from @result r
			left join events e with(nolock) on e.event_id = r.last_event_id
			left join mols m with(nolock) on m.mol_id = r.owner_mol_id
			left join mols m2 with(nolock) on m2.mol_id = isnull(e.mol_id, r.last_mol_id)
		order by
			case when r.count_unreads > 0 then 0 else 1 end,
			r.last_date desc
end
go
-- helper: Вовзращает кол-во непрочтённых сообщений одного пользователя
create proc events_get_groups;10
	@mol_id int
as
begin
	
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	declare @count int = 0

	-- talks
	select @count = @count + isnull(count(distinct t.talk_id),0) 
		from talks_mols tm with(nolock)
			join talks t with(nolock) on t.talk_id = tm.talk_id
		where tm.mol_id = @mol_id and tm.is_deleted = 0
			and tm.count_unreads > 0

	-- tasks
	select @count = @count + count(distinct h.task_id) 
		from tasks_hists_mols hm with(nolock)
			join tasks_hists h with(nolock) on h.hist_id = hm.hist_id
		where hm.mol_id = @mol_id and hm.d_read is null 
			and h.silence = 0

	select @count	
end
go
-- helper: вовзращает кол-во непрочтённых сообщений всех пользователей
create proc events_get_groups;20
as
begin

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	create table #counts(mol_id int, count_reads int, count_unreads int)

	-- events
		-- unreads
		insert into #counts(mol_id, count_unreads)
		select em.mol_id,  count(*) 
		from events e
			join events_mols em on em.event_id = e.event_id and em.read_date is null
			join events_feeds_types ft on ft.feed_type_id = e.feed_type_id
		where ft.is_alert = 1
		group by em.mol_id
		
		-- reads
		insert into #counts(mol_id, count_reads)
		select em.mol_id,  count(*) 
		from events e
			join events_mols em on em.event_id = e.event_id and em.read_date is not null
			join events_feeds_types ft on ft.feed_type_id = e.feed_type_id
		where ft.is_alert = 1
		group by em.mol_id

	-- talks
		-- unreads
		insert into #counts(mol_id, count_unreads)
		select mol_id, sum(count_unreads)
		from talks_mols
		group by mol_id
		having sum(count_unreads) > 0

		-- reads
		insert into #counts(mol_id, count_reads)
		select mol_id, sum(1) from talks_reads group by mol_id

	-- tasks
		-- reads
		insert into #counts(mol_id, count_reads)
		select mol_id, count(*) from tasks_hists_mols where d_read is not null
		group by mol_id
		-- unreads
		insert into #counts(mol_id, count_unreads)
		select mol_id, count(*) from tasks_hists_mols where d_read is null
		group by mol_id

		-- result
		select *		
		from (
			select 
				mol_id,
				isnull(sum(count_reads),0) as count_reads,
				isnull(sum(count_unreads),0) as count_unreads
			from #counts c
			group by mol_id
			) r
		where count_unreads > 10
		
end
go
