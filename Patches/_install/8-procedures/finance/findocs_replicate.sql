if object_id('findocs_replicate') is not null drop proc findocs_replicate
go
create proc findocs_replicate
	@mol_id int = -25,
	@date_from datetime = null,
	@date_to datetime = null,
	@subject_id int = null,
	@debug bit = 0
as
begin

	set nocount on;

	-- params
		declare @proc_name varchar(50) = object_name(@@procid)
		declare @tid int; exec tracer_init @proc_name, @trace_id = @tid out

		declare @tid_msg varchar(max) = concat(@proc_name, '.params:', 
			' @mol_id=', @mol_id,
			' @date_from=', dbo.date2str(@date_from, default),
			' @date_to=', dbo.date2str(@date_to, default),
			' @subject_id=', @subject_id
			)
		exec tracer_log @tid, @tid_msg
			
		--if @debug = 0
		--begin
		--	raiserror('Процедура репликации временно отключена.', 16, 1)
		--	return
		--end
		
		if @subject_id is null
		begin
			raiserror('Необходимо указать субъект учёта для репликации оплат.', 16, 1)
			return
		end

		declare @DATE_FIXED datetime = '2017-01-01'

		create table #buffer (findoc_id int, subject_id int, extern_id int)
		
		declare @subjects_excluded table (subject_id int)
		insert into @subjects_excluded values (7),(15134),(9)

			if exists(select 1 from  @subjects_excluded where subject_id = @subject_id)
			begin
				raiserror('По выбранному субъекту учёта репликация оплат отключена.', 16, 1)
				return
			end

		declare @subjects table (subject_id int);
		insert into @subjects select subject_id from subjects where subject_id <> 0
			and subject_id not in (select subject_id from @subjects_excluded)

	-- #pays
		declare @skip_prepare_pays bit = 
			case
				when object_id('tempdb.dbo.#pays') is null then 0
				else 1
			end

	-- #tables
		if @skip_prepare_pays = 0
		begin
			create table #pays (
				row_id int identity primary key, -- суррогатный ключ для работы с множеством	
				findoc_id int NULL,
				UniqueId varchar(64),
				DocId int,
				DocDate datetime NOT NULL,
				SubjectId int NOT NULL,
				SubjectName varchar(150) NOT NULL,
				AccId int NOT NULL,
				AccNo varchar(50) NOT NULL,
				AccName varchar(50) NOT NULL,
				DocNo varchar(100),
				agent_id int, -- > инициируется далее
				AgentId int, -- > agents.external_id
				AgentName varchar(255),
				AgentINN varchar(30),
				AgentAcc varchar(50),
				AgentAnalyt varchar(255),
				Cause varchar(500),
				budget_id int,
				BudgetName varchar(255),
				article_id int,
				ArticleName varchar(255),
				CcyId char(3),
				ValueCcy float NOT NULL default(0),
				ValueRur float NOT NULL default(0)		
			)

			create table #pays_details (
				UniqueId varchar(64),
				findoc_id int NULL,
				budget_id int,
				BudgetName varchar(255),
				article_id int,
				ArticleName varchar(255),
				ValueCcy float NOT NULL default(0),
				ValueRur float NOT NULL default(0)
			)
		end

	-- @date_from, @date_to
		if @date_from is null set @date_from = dateadd(d, -10, dbo.today())	
		if @date_from < @DATE_FIXED
		begin
			declare @dateFixedText varchar(20) = convert(varchar, @DATE_FIXED, 104)
			raiserror('Журнал оплат зафиксирован на %s включительно. За более ранний период репликация оплат невозможна.', 16, 1, @dateFixedText)
			return
		end

		if @date_to is null set @date_to = dbo.today()

	-- prepare pays
		if @skip_prepare_pays = 0
		begin
			-- prepare_pays
				exec budgetdb.dbo.prepare_pays @date_from = @date_from, @date_to = @date_to, @subject_id = @subject_id
		
			-- #bad_accids
				create table #bad_accids(AccId int primary key)
				--insert into #bad_accids(AccId)
				--values (30), (135), (157)  -- TODO: кредитная линия ТД !!!!

			-- #pays
				insert into #pays (
					UniqueId, DocId, 
					DocDate, DocNo, SubjectId, SubjectName,
					AccId, AccNo, AccName, 
					AgentId, AgentName, AgentINN, AgentAcc, AgentAnalyt,
					budget_id, BudgetName, article_id, ArticleName,
					CcyId, ValueCcy, ValueRur,
					Cause
					)
				select
					UniqueId, DocId,
					DocDate, DocNo, SubjectId, SubjectName,
					AccId,
					case when AccNo = '-' then AccName + ' (' + s.short_name + ')' else AccNo end,
					AccName,
					p.AgentId, ltrim(rtrim(coalesce(AgentName, Analyt, '-'))), AgentINN, AgentAcc, Analyt,
					budget_id, ltrim(rtrim(BudgetName)), article_id, ltrim(rtrim(ArticleName)),
					p.ccyid,
					isnull(SumDt,0) - isnull(SumKt,0),
					isnull(RurDt,0) - isnull(RurKt,0),
					Cause
				from budgetdb.dbo.doc_paysh p
					join subjects s on s.subject_id = p.SubjectId
				where p.DocDate between @date_from and @date_to
					and p.SubjectId in (select subject_id from @subjects)
					and (@subject_id is null or p.SubjectId = @subject_id)
					and not exists(select 1 from #bad_accids where AccId = p.AccId)
			
			-- #pays_details
				insert into #pays_details(UniqueId, budget_id, BudgetName, article_id, ArticleName, ValueCcy, ValueRur)
				select d.UniqueId, d.budget_id, ltrim(rtrim(d.BudgetName)), d.article_id, ltrim(rtrim(d.ArticleName)),
					isnull(d.SumDt,0) - isnull(d.SumKt,0),
					isnull(d.RurDt,0) - isnull(d.RurKt,0)
				from budgetdb.dbo.doc_paysd d
					join #pays h on h.UniqueId = d.UniqueId
		end

	-- #PAYS, #PAYS_DETAILS > FINDOCS, FINDOCS_DETAILS
		exec findocs_replicate;2 @append_only = @skip_prepare_pays

		exec tracer_close @tid
end
GO
-- helper: #PAYS, #PAYS_DETAILS > FINDOCS, FINDOCS_DETAILS
create proc findocs_replicate;2
	@append_only bit = 0
as
begin

	-- params
		declare @date_from datetime = (select min(DocDate) from #pays)
		declare @date_to datetime = (select max(DocDate) from #pays)
		declare @subject_id int = case when (select count(distinct SubjectId) from #pays) = 1 then (select distinct SubjectId from #pays) end

	-- save old findocs
		select * into #findocs from findocs 
		where d_doc between @date_from and @date_to
			and (@subject_id is null or subject_id = @subject_id)
	
	-- save old findocs_details
		select * into #findocs_details from findocs_details x
		where findoc_id in (select findoc_id from #findocs)
			-- Если есть хотя бы одна строка НЕ РАЗНЕСЕНО, то перезакачиваем детлизацию заново
			and not exists(
				select 1 from findocs_details 
				where findoc_id = x.findoc_id 
					and (isnull(budget_id,0) = 0 or isnull(article_id,0) = 0)
				)

	-- process transaction
	BEGIN TRY
		BEGIN TRANSACTION
		-- авто-српавочники
			exec findocs_replicate;20

		-- calc findoc_id
			exec findocs_replicate;30
		-- delete olds
			if @append_only = 0
			begin
				-- #findocs_details
				delete from findocs_details where findoc_id in (select findoc_id from #findocs)
				-- #findocs
				delete from findocs where findoc_id in (select findoc_id from #findocs)
			end

		-- insert FINDOCS
			insert into findocs (
				findoc_id, extern_id,
				subject_id,
				account_id,
				d_doc, number,
				agent_id, agent_inn, agent_acc, agent_analyt,
				budget_id,
				article_id,
				goal_account_id,
				note,
				ccy_id,
				value_ccy,
				value_rur,
				talk_id
			)
			select
				p.findoc_id, p.DocId,
				p.SubjectId,
				fa.account_id,
				p.DocDate, p.DocNo,
				p.agent_id, p.AgentINN, p.AgentAcc, p.AgentAnalyt,
				coalesce(nullif(fd.budget_id,0), p.budget_id, 0),
				coalesce(nullif(fd.article_id,0), p.article_id, 0),
				fd.goal_account_id,
				p.Cause,
				p.CcyId,
				p.ValueCcy,
				p.ValueRur,
				fd.talk_id
			from #pays p
				join findocs_accounts fa on fa.subject_id = p.SubjectId and fa.external_id = p.AccId
				left join #findocs fd on fd.findoc_id = p.findoc_id

		-- insert FINDOCS_DETAILS
			if @append_only = 0
			begin
				insert into findocs_details(findoc_id, goal_account_id, budget_id, article_id, value_ccy, value_rur)
				select p.findoc_id, fd.goal_account_id, d.budget_id, d.article_id, d.ValueCcy, d.ValueRur
				from #pays_details d
					join #pays p on p.UniqueId = d.UniqueId
						join #findocs fd on fd.findoc_id = p.findoc_id
				where p.findoc_id not in (select findoc_id from #findocs_details)

				-- insert old findocs_details (if any)
				;SET IDENTITY_INSERT CISP_SHARED..FINDOCS_DETAILS ON;
					insert into findocs_details(id, findoc_id, goal_account_id, budget_id, article_id, value_ccy, value_rur, note)
					select id, findoc_id, goal_account_id, budget_id, article_id, value_ccy, value_rur, note
					from #findocs_details
					where findoc_id in (select findoc_id from findocs)
				;SET IDENTITY_INSERT CISP_SHARED..FINDOCS_DETAILS OFF;
			end
			
			else begin
				insert into findocs_details(findoc_id, goal_account_id, budget_id, article_id, value_ccy, value_rur)
				select p.findoc_id, fd.goal_account_id, d.budget_id, d.article_id, d.ValueCcy, d.ValueRur
				from #pays_details d
					join #pays p on p.UniqueId = d.UniqueId
						join #findocs fd on fd.findoc_id = p.findoc_id
			end

		-- map agents
			update x
			set agent_id = pa.agent_id
			from findocs x
				join #pays xp on xp.findoc_id = x.findoc_id
				join agents a on a.agent_id = x.agent_id
					join agents pa on pa.agent_id = a.main_id

		COMMIT TRANSACTION
	END TRY

	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
		declare @err varchar(max); set @err = error_message()
		raiserror (@err, 16, 3)
	END CATCH
end
GO
-- helper: process dictionaries
create proc findocs_replicate;20
as
begin

	-- SUBJECTS
		insert into subjects(subject_id, name)
		select distinct SubjectId, SubjectName from #pays
		where SubjectId not in (select subject_id from subjects)

	-- FINDOCS_ACCOUNTS
		insert into findocs_accounts(subject_id, external_id, number, name)
		select distinct SubjectId, AccId, AccNo, AccName
		from #pays p
		where not exists(select 1 from findocs_accounts where subject_id = p.SubjectId and external_id = p.AccId)

	-- AGENTS
		-- by inn
			insert into agents(name, name_print, inn)
			select distinct AgentName, AgentName, AgentINN
			from #pays x
			where len(AgentINN) >= 10
				and not exists(
					select 1 from agents where status_id >= 0 and len(inn) >= 10
					and inn = x.AgentINN
					)

			update x
			set agent_id = a.agent_id
			from #pays x
				join (
					select inn, agent_id = min(agent_id) from agents
					where status_id = 1 and len(inn) >= 10
					group by inn
					having count(*) <= 3
				) a on a.inn = x.AgentINN
			where len(x.AgentINN) >= 10

		-- by name		
			insert into agents(name, name_print, inn)
			select distinct AgentName, AgentName, AgentINN
			from #pays
			where agent_id is null
				and AgentName not in (select name from agents)
				and AgentName <> '-'

			update x
			set agent_id = isnull(a.main_id, a.agent_id)
			from #pays x
				join agents a on a.name = x.AgentName
			where x.agent_id is null

	-- -- AGENTS
	-- 	insert into agents(name, name_print, inn)
	-- 	select distinct AgentName, AgentName, AgentINN
	-- 	from #pays
	-- 	where AgentName not in (select name from agents)
	-- 		and AgentName <> '-'

	-- 	update x
	-- 	set agent_id = a.agent_id
	-- 	from #pays x
	-- 		join agents a on a.name = x.AgentName

	-- 	update a
	-- 	set external_id = x.AgentId
	-- 	from #pays x
	-- 		join agents a on a.agent_id = x.agent_id

	-- BDR_ARTICLES
		update #pays set article_id = 0
		update #pays_details set article_id = 0

	-- BUDGETS
		update #pays set budget_id = 0
		update #pays_details set budget_id = 0
	
end
GO
-- helper: build FINDOC_ID
create proc findocs_replicate;30
as
begin

	-- old ids
	update #pays set findoc_id = fd.findoc_id
	from #pays
		join #findocs fd on fd.subject_id = #pays.SubjectId and fd.extern_id = #pays.DocId

	-- seed
	declare @maxid int; select @maxid = isnull(max(findoc_id),1) from findocs

	-- new ids
	select row_id, @maxid + row_number() over (order by row_id) as findoc_id
	into #news from #pays where findoc_id is null

	update #pays set findoc_id = #news.findoc_id
	from #pays
		join #news on #news.row_id = #pays.row_id
end
GO
