if object_id('agents_calc') is not null drop proc agents_calc
go
-- exec agents_calc 700
create proc agents_calc
	@mol_id int
as
begin

	set nocount on;

-- map
	declare @map table(agent_id int primary key, main_id int)
		insert into @map(agent_id, main_id)
		select agent_id, main_id
		from agents
		where main_id is not null

exec sys_set_triggers 0

-- findocs
	update x
	set agent_id = m.main_id
	from findocs x
		join @map m on m.agent_id = x.agent_id
	where x.agent_id <> m.main_id

-- deals
	update x
	set customer_id = m.main_id
	from deals x
		join @map m on m.agent_id = x.customer_id
	where x.customer_id <> m.main_id

	update x
	set consumer_id = m.main_id
	from deals x
		join @map m on m.agent_id = x.consumer_id
	where x.consumer_id <> m.main_id

-- projects_contracts
	update x
	set customer_id = m.main_id
	from projects_contracts x
		join @map m on m.agent_id = x.customer_id
	where x.customer_id <> m.main_id

-- plan_pays_rows
	update x
	set agent_id = m.main_id
	from plan_pays_rows x
		join @map m on m.agent_id = x.agent_id
	where x.agent_id <> m.main_id

	update x
	set agent_id = m.main_id
	from plan_pays_az x
		join @map m on m.agent_id = x.agent_id
	where x.agent_id <> m.main_id

-- sdocs
	update x
	set agent_id = m.main_id
	from sdocs x
		join @map m on m.agent_id = x.agent_id
	where x.agent_id <> m.main_id

exec sys_set_triggers 1

-- авто-архивирование дубликатов
	update agents
	set status_id = 10
	where status_id <> 10
		and main_id is not null

-- авто-архивирование не используемых контрагентов
	--;with ag as (
	--	select distinct agent_id from findocs where agent_id is not null
	--	union select distinct agent_id from payorders where agent_id is not null
	--	union select distinct pred_id from subjects where pred_id is not null
	--	union select distinct x.customer_id from deals x where customer_id is not null
	--	union select distinct x.consumer_id from deals x where consumer_id is not null
	--	)
	--update agents set status_id = 10
	--where agent_id not in (select agent_id from ag)
	--	and status_id = 1

end
GO
