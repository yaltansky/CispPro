if object_id('mfr_autoadmin') is not null drop proc mfr_autoadmin
go
create proc mfr_autoadmin
as
begin
	set nocount on;

    -- bad refs on talks
		EXEC SYS_SET_TRIGGERS 0

			update x set talk_id = null
			from mfr_sdocs_contents x where talk_id is not null
				and not exists(select 1 from talks where talk_id = x.talk_id)

			update x set talk_id = null
			from mfr_sdocs_milestones x where talk_id is not null
				and not exists(select 1 from talks where talk_id = x.talk_id)

		EXEC SYS_SET_TRIGGERS 1

	-- -- opers
	-- 	-- auto-dictionary
	-- 	insert into mfr_places_opers(place_id, name)
	-- 	select distinct o.place_id, o.name
	-- 	from mfr_drafts_opers o
	-- 		join mfr_drafts d on d.draft_id = o.draft_id and d.is_buy = 0
	-- 		join mfr_places pl on pl.place_id = o.place_id
	-- 	where isnull(o.is_deleted,0) = 0
	-- 		and o.place_id is not null
	-- 		and o.name is not null
	-- 		and not exists(select 1 from mfr_places_opers where place_id = o.place_id and name = o.name)

	-- empty jobs
		update x set status_id = -1
		from mfr_plans_jobs x
		where type_id = 1 and not exists(select 1 from mfr_plans_jobs_details where plan_job_id = x.plan_job_id)

    -- mfr_drafts_pdm
        update x set pdm_id = null
        from mfr_drafts x
            join mfr_pdms p on p.pdm_id = x.pdm_id and p.item_id != x.item_id

        delete x from mfr_drafts_pdm x
            join mfr_drafts d on d.draft_id = x.draft_id
            join mfr_pdms p on p.pdm_id = x.pdm_id
        where d.item_id != p.item_id

	-- misc
		delete from clr_gantts
end
go
