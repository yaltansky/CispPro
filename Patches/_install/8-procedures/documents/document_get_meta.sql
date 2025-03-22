if object_id('document_get_meta') is not null drop proc document_get_meta
go
create proc document_get_meta
	@mol_id int,
	@document_id int
as
begin

	set nocount on;

-- @owner_id, @owner_key, @owner_name
	declare @owner_id int, @owner_key varchar(32), @owner_name varchar(250)

	exec document_get_owner @document_id = @document_id, @owner_id = @owner_id out, @owner_key = @owner_key out
	select @owner_name = name from documents where key_owner_id = @owner_id

-- @refkey, @opened_agree_id
	declare @refkey varchar(250), @key_attachments varchar(max), @opened_agree_id int
	select
		@refkey = refkey,
		@key_attachments = key_attachments,
		@opened_agree_id = last_agree_id
	from documents
	where document_id = @document_id

-- @is_admin
	declare @is_admin bit = dbo.isinrole(@mol_id, 'Projects.Admin,Documents.Admin')

-- @is_moderator
	declare @is_moderator bit = 
		case
			when @is_admin = 1
				or exists(select 1 from documents where document_id = @document_id and @mol_id in (mol_id, response_id))
				or exists(select 1 from documents_mols where document_id = @document_id and mol_id = @mol_id and a_update = 1) 
				then 1
			else 0
		end

	declare @closed_agree_id int = (
		select max(task_id) from tasks x where type_id = 2 and refkey = @refkey
			and not exists(select 1 from tasks_mols where task_id = x.task_id and role_id = 1 and d_executed is null)
		)

	declare @closed_agree_key varchar(250) = (
		'/files/tasks/' + cast(@closed_agree_id as varchar) + '/hist' + 
		cast((select top 1 hist_id from tasks_hists where task_id = @closed_agree_id order by hist_id) as varchar)
		)

-- LAST_AGREE_MOLS
	declare @last_agree_mols_count int, @last_agree_mols varchar(max)

	set @last_agree_mols_count = (select count(*) from tasks_mols where task_id = @closed_agree_id and role_id = 1)
	set @last_agree_mols = (
			select top 10 cast(m.name as varchar) + ', ' as [text()]
			from tasks_mols tm
				inner join mols m on m.mol_id = tm.mol_id
			where tm.task_id = @closed_agree_id
				and role_id = 1
			order by m.name
			for xml path('')
			)
		-- убрать последнюю запятую
		if len(@last_agree_mols) > 1
			set @last_agree_mols = substring(@last_agree_mols, 1, len(@last_agree_mols) - 1)

	if @last_agree_mols_count > 10
		set @last_agree_mols = @last_agree_mols + ' ... (всего ' + cast(@last_agree_mols_count as varchar) + ')'

-- results
	select 
		DOCUMENT_ID = @document_id,
		OWNER_KEY = @owner_key,
		OWNER_ID = @owner_id,
		OWNER_NAME = isnull(@owner_name, ''),
		OWNER_REF = isnull(@owner_key, ''),
		IS_ADMIN = @is_admin,
		
		ALLOW_EDIT = @is_moderator,
		
		ALLOW_COMPLETE = cast(
			case 
				when type_id = 2 then
					case				
						when status_id in (0, 3) and @is_moderator = 1 then 1 
						else 0 
					end
				else 
					case
						when @opened_agree_id is null and status_id <> 10 then 1 
						else 0
					end
			end as bit),
		
		ALLOW_AGREE = cast(
			case 
				when @is_admin = 1 and status_id = 1 then 1
				else 0
			end as bit),
						
        ALLOW_NEW_ROUTER = cast(
			case 
				when @opened_agree_id is not null then 0
				else 
					case 
						when type_id = 2 then 
							case when status_id not in (-2,-1,2) then 1 end
						else @is_moderator
					end
			end as bit),
        
		ALLOW_NEW_MAILLIST = cast(
			case when status_id = 10 then 1 end 
			as bit),
        
		ALLOW_NEW_TASK = @is_moderator,
		ALLOW_NEW_ASSIGN = @is_moderator,
		
		LAST_AGREE_ID = @closed_agree_id,
		LAST_VERSION_KEY = @key_attachments,
			--case
			--	when @is_moderator = 1 or status_id = 10 then @key_attachments
			--	else @closed_agree_key
			--end,
		LAST_AGREE_MOLS = @last_agree_mols
	from documents
	where document_id = @document_id

end
GO
