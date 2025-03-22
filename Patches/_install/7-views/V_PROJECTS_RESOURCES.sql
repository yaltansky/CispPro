IF OBJECT_ID('V_PROJECTS_RESOURCES') IS NOT NULL DROP VIEW V_PROJECTS_RESOURCES
GO
CREATE VIEW V_PROJECTS_RESOURCES
AS
select
	R.RESOURCE_ID,	
	R.TYPE_ID,
	TYPE_NAME = T.NAME,
	R.NAME,
	R.AGGREGATION_ID,
	AGGREGATION_NAME = A.NAME,
	R.DISTRIBUTION_ID,
	DISTRIBUTION_NAME = D.NAME,
	R.LIMIT_Q,
	R.PRICE,
	R.DESCRIPTION,
	--
	R.NODE,
	R.PARENT_ID,
	R.HAS_CHILDS,
	R.LEVEL_ID,	
	R.IS_DELETED,
	R.SORT_ID,
	R.MOL_ID,
	R.ADD_DATE	
from projects_resources r
	left join projects_resources_types t on t.type_id = r.type_id
	left join projects_resources_aggregations a on a.aggregation_id = r.aggregation_id
	left join projects_resources_distributions d on d.distribution_id = r.distribution_id
GO
