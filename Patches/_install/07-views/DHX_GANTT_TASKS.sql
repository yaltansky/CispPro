/****** Object:  View [DHX_GANTT_TASKS]    Script Date: 9/18/2024 3:26:25 PM ******/
IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[DHX_GANTT_TASKS]'))
EXEC dbo.sp_executesql @statement = N'
CREATE VIEW [DHX_GANTT_TASKS]
AS

select
	pp.project_id,
	pp.task_id as id,
	pp.task_number,
	pp.predecessors,
	pp.name as text,
	pp.d_from as start_date,
	pp.d_to as end_date,
	pp.duration,
	pp.progress,
	pp.sort_id as sortorder,
	pp.parent_id as parent,
	case when pp.duration = 0 then ''milestone'' else ''task'' end as type,
	pp.has_childs as ''open'',
	pp.base_d_from as base_start,
	pp.base_d_to as base_end,
	pp.duration_buffer,
	pp.is_critical,
	case 
		when pp.has_childs = 0 and pp.is_critical = 1 then ''К'' 
		when pp.has_childs = 0 and isnull(pp.is_long,0) = 1 then ''Б'' + cast(pp.duration_buffer as varchar)
	end as ''is_critical_label'',
	cast(0 as bit) as is_long, -- formal field (readonly)
	pp.outline_level,
	0 as execute_level
from projects_tasks pp

' 
GO
