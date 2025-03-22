if object_id('talks_autoadmin') is not null	drop proc talks_autoadmin
go
create proc talks_autoadmin
as
begin

	set nocount on;

	IF DB_NAME() NOT IN ('CISP') RETURN

	declare @today datetime = dbo.today()

	update x
	set x.is_deleted = 1
	from talks_mols x
		join (
			select parent_id as talk_id, max(d_add) as d_add
			from talks_hists
			group by parent_id
		) h on h.talk_id = x.talk_id
	where datediff(d, h.d_add, @today) > 30

	-- удалить пустые комментарии (пока те, что используются в проектаx)
	select x.talk_id into #emptyTalks
	from talks x
	where not exists(
		select 1 from talks_hists where parent_id = x.talk_id and body is not null
		)
		and exists(
			select 1 from projects_tasks where talk_id = x.talk_id
		)

	update projects_tasks set talk_id = null where talk_id in (select talk_id from #emptyTalks)

	delete from talks_hists where parent_id in (select talk_id from #emptytalks)
	delete from talks where talk_id in (select talk_id from #emptytalks)
	
	drop table #emptyTalks

	-- удалить пустые реплики
	delete from talks_hists where isnull(body,'') = '' and d_add < @today

	-- удалить пустые диалоги
	delete x from talks x
	where not exists(select 1 from talks_hists where parent_id = x.talk_id)

	-- очистить ссылки
	update x set talk_id = null 
	from projects_tasks x
	where talk_id is not null
		and not exists(select 1 from talks where talk_id = x.talk_id)
end
go
