USE CISP_SHARED
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[MOLS_EMPLOYEES]') AND type in (N'U'))
BEGIN
CREATE TABLE MOLS_EMPLOYEES(
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[MOL_ID] [int] NULL,
	[SUBJECT_ID] [int] NULL,
	[BRANCH_ID] [int] NULL,
	[DEPT_ID] [int] NULL,
	[POST_ID] [int] NULL,
	[DATE_HIRE] [datetime] NULL,
	[DATE_FIRE] [datetime] NULL,
	[K_PARTIAL] [decimal](3, 2) NULL DEFAULT ((1.00)),
	[IS_DELETED] [bit] NOT NULL DEFAULT ((0)),
	[ADD_DATE] [datetime] DEFAULT getdate(),
	[ADD_MOL_ID] [int] NULL,
	[UPDATE_DATE] [datetime] NULL,
	[UPDATE_MOL_ID] [int] NULL,
	[RATE_PRICE] [float] NULL,
	[TAB_NUMBER] [varchar](50) NULL,
	[SALE_PRICE] [float] NULL,
    PRIMARY KEY CLUSTERED 
    (
        [ID] ASC
    )
)
END
GO

IF NOT EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N'[tiud_mols_employee]'))
EXEC sp_executesql @statement = N'create trigger [tiud_mols_employee] on [MOLS_EMPLOYEES]
for insert, update, delete
as
begin

	set nocount on;

	declare @depts_names varchar(max), @posts_names varchar(max)

	update x
	set 
		@depts_names = (
			select dept_name + ''; ''  [text()] 
			from (
				select distinct d.name as dept_name
				from mols_employees me
					join depts d on d.dept_id = me.dept_id
				where me.mol_id = x.mol_id
					and me.date_fire is null
                    and me.is_deleted = 0
				) pp
			for xml path('''')
			),
		@posts_names = (
			select post_name + ''; ''  [text()] 
			from (
				select distinct mp.name as post_name
				from mols_employees me
					join mols_posts mp on mp.post_id = me.post_id
				where me.mol_id = x.mol_id
					and me.date_fire is null
                    and me.is_deleted = 0
				) pp
			for xml path('''')
			),
		subject_id = nullif(
            isnull(
                (
			    select top 1 subject_id from mols_employees e
			    where mol_id = x.mol_id and isnull(k_partial, 1) = 1
                    and e.is_deleted = 0
			    ), 
                (
			    select top 1 subject_id from mols_employees e
			    where mol_id = x.mol_id
                    and e.is_deleted = 0
			    )
            ), 0),
		city_name = isnull((
			select top 1 c.name
			from mols_employees e
				join branches b on b.branch_id = e.branch_id
					join cities c on c.city_id = b.city_id
			where e.mol_id = x.mol_id
				and isnull(e.k_partial, 1) = 1
                and e.is_deleted = 0
            ), city_name),
		depts_names = left(
			case 
				when len(@depts_names) > 1 then left(@depts_names, len(@depts_names) - 1)
			end, 250
			),
		posts_names = left(
			case 
				when len(@posts_names) > 1 then left(@posts_names, len(@posts_names) - 1)
			end, 250
			),
        tab_number = isnull((
			select top 1 e.tab_number
			from mols_employees e
			where e.mol_id = x.mol_id
                and date_hire is not null
                and isnull(e.k_partial, 1) = 1
				and is_deleted = 0
            ), tab_number)
	from mols x
	where x.mol_id in (
		select mol_id from inserted
		union select mol_id from deleted
		)

	update x
	set post_id = coalesce(
					(select top 1 post_id from mols_employees where mol_id = x.mol_id and date_hire is not null and is_deleted = 0 order by date_hire desc),
					(select top 1 post_id from mols_employees where mol_id = x.mol_id and is_deleted = 0),
					post_id
					)
	from mols x
	where mol_id in (select mol_id from inserted)

	update x
	set dept_id = me.dept_id,
		chief_id = depts.chief_id
	from mols x
		join mols_employees me on me.mol_id = x.mol_id and me.date_fire is null and isnull(me.k_partial, 1) = 1 and me.is_deleted = 0
		    join depts on depts.dept_id = me.dept_id
	where x.mol_id in (
		select mol_id from inserted
		union select mol_id from deleted
		)

end -- trigger
' 
GO
