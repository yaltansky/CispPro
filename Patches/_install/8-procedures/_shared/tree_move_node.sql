if object_id('tree_move_node') is not null drop procedure tree_move_node
go
create procedure tree_move_node
	@table_name varchar(50),
	@key_name varchar(50),
	@where_rows nvarchar(250) = null,
	@source_id int,
	@target_id int = null,
	@where varchar(10) = 'into',
	@script_after_update varchar(1000) = '',
    @mol_id int = null
as  
begin  
	set nocount on;

declare @sql nvarchar(max) = N'
	declare @affected table(id int)
		insert into @affected values (@source_id), (@target_id)
		insert into @affected select parent_id from documents where document_id = @source_id

	declare @source hierarchyid = (select node from documents where document_id = @source_id);
	declare @parent hierarchyid, @parent_id int, @new_place hierarchyid

	SET TRANSACTION ISOLATION LEVEL SERIALIZABLE
	BEGIN TRANSACTION

		declare @target hierarchyid, @child2 hierarchyid

		if @target_id is null
		begin
			select @new_place = hierarchyid::GetRoot().GetDescendant(max(node), null)   
			from documents where <where_rows> parent_id is null

			update documents 
			set node = @new_place,
				parent_id = null
                <timestamp>
			where document_id = @source_id
		end

		else if @where = ''into''
		begin
			select @parent = node from documents where document_id = @target_id;
			set @parent_id = @target_id
		
			select @new_place = @parent.GetDescendant(max(node), null)   
			from documents where <where_rows> node.GetAncestor(1) = @parent;
		end

		else if @where = ''first''
		begin
			-- @parent_id, @parent
			set @parent_id = @target_id;
			select @parent = node from documents where document_id = @parent_id;
			if @parent is null set @parent = hierarchyid::GetRoot();

			-- @child2
			select @child2 = min(node) from documents 
			where <where_rows>
				(@parent_id is null and parent_id is null) or (parent_id = @parent_id)
				and is_deleted = 0

			-- @new_place
			select @new_place = @parent.GetDescendant(null, @child2)
		end

		else if @where = ''after''
		begin
			-- @parent_id, @parent
			select @parent_id = parent_id from documents where document_id = @target_id;
				select @parent = node from documents where document_id = @parent_id;
				if @parent is null set @parent = hierarchyid::GetRoot();

			-- @target
			select @target = node from documents where document_id = @target_id;
						
			-- @child2
			select @child2 = min(node) from documents 
				where <where_rows>
					((@parent_id is null and parent_id is null) or parent_id = @parent_id)
					and node > @target
					and is_deleted = 0

			-- move
			select @new_place = @parent.GetDescendant(@target, @child2)
		end

		if @parent.IsDescendantOf(@source) = 1
		begin
			ROLLBACK TRANSACTION
			raiserror(''Родительский документ нельзя перемещать в свой дочерний элемент.'', 16, 1)
			return
		end			

		if @source is not null
			-- reparent childs
			update documents    
			set node = node.GetReparentedValue(@source, @new_place)
                <timestamp>
			where <where_rows> node.IsDescendantOf(@source) = 1;
		else
			-- new document
			update documents set node = @new_place
                <timestamp>
            where document_id = @source_id

		-- reparent node
		update documents set parent_id = @parent_id
            <timestamp>
        where document_id = @source_id

		-- has_childs
		update x
		set has_childs = 
				case
					when exists(select 1 from documents where <where_rows> parent_id = x.document_id and is_deleted = 0) then 1
					else 0
				end
            <timestamp>
		from documents x
		where x.document_id in (select id from @affected where id is not null)
		
		<stmt_sorting>

		<stmt_after_update>

	COMMIT TRANSACTION  
'

set @sql = replace(@sql, '<stmt_sorting>', 
	case
		when exists(select 1 from sys.columns where name = 'sort_id' and object_name(object_id) = @table_name) then '
			update x
			set sort_id = xx.number
			from documents x
				join (
					select document_id, row_number() over (order by node) as number
					from documents
					where <where_rows> is_deleted = 0
				) xx on xx.document_id = x.document_id
			where sort_id <> xx.number
			'
		else ''
	end
	)

set @sql = replace(@sql, 'documents', @table_name)
set @sql = replace(@sql, 'document_id', @key_name)
set @sql = replace(@sql, '<where_rows>', isnull(@where_rows + ' and ', ''))
set @sql = replace(@sql, '<stmt_after_update>', isnull(@script_after_update, ''))
set @sql = replace(@sql, '<timestamp>', 
    case
        when @mol_id is null then ''
        else concat(', update_date = getdate(), update_mol_id = ', @mol_id)
    end
    )

exec sp_executesql @sql,
	N'@source_id int, @target_id int, @where varchar(10)', 
	@source_id, @target_id, @where

end
go
